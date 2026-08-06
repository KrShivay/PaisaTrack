import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/models/normalized_transaction_record.dart';
import '../intelligence/models/embedder.dart';
import 'counterparty_key.dart';
import 'payee_identity_key.dart';

/// Result of resolving parser text to a canonical merchant (PLAN §7.3).
class MerchantResolution {
  const MerchantResolution({
    this.merchantId,
    this.canonicalName,
    this.embedding,
    required this.confidence,
    required this.source,
    this.needsReview = false,
  });

  final String? merchantId;
  final String? canonicalName;
  final Float32List? embedding;
  final double confidence;
  final String source;
  final bool needsReview;
}

/// Resolves normalized aliases first, then compares local embeddings.
///
/// The full merchant table is intentionally scanned: private databases stay
/// below two thousand merchants, making a deterministic brute-force cosine
/// search cheaper and less error-prone than maintaining an ANN index.
class MerchantResolver {
  MerchantResolver(this._database, this._embedder);

  static const autoLinkThreshold = .92;
  static const reviewThreshold = .75;

  final AppDatabase _database;
  final Embedder _embedder;

  Future<MerchantResolution> resolve(NormalizedTransactionRecord record) async {
    final counterparty = const CounterpartyKeyParser().parse(
      vpa: record.counterpartyVpa,
      merchantRaw: record.merchantRaw,
    );

    if (record.merchantRaw == null &&
        (counterparty.kind == CounterpartyKind.person || counterparty.kind == CounterpartyKind.self)) {
      return MerchantResolution(
        merchantId: null,
        canonicalName: record.counterpartyVpa ?? counterparty.inferredName ?? counterparty.displayName ?? 'P2P Transfer',
        confidence: 1.0,
        source: 'counterparty_person',
        needsReview: false,
      );
    }

    final raw = record.merchantRaw ?? record.counterpartyVpa;
    if (raw == null || raw.trim().isEmpty) {
      return const MerchantResolution(confidence: 0, source: 'none');
    }
    final alias = normalizeAlias(raw);
    final aliasRow = await (_database.select(_database.merchantAliases)
          ..where((row) => row.alias.equals(alias)))
        .getSingleOrNull();
    if (aliasRow != null) {
      final merchant = await (_database.select(_database.merchants)
            ..where((row) => row.id.equals(aliasRow.merchantId)))
          .getSingleOrNull();
      if (merchant != null) {
        final needsReview = aliasRow.source == 'similarity';
        return MerchantResolution(
          merchantId: merchant.id,
          canonicalName: merchant.canonicalName,
          embedding: _decode(merchant.embedding),
          confidence: needsReview ? aliasRow.confidence : 1,
          source: aliasRow.source,
          needsReview: needsReview,
        );
      }
    }

    final embedding = await _embedder.embed(alias);
    if (embedding == null) {
      return MerchantResolution(
        canonicalName: raw.trim(),
        confidence: 0,
        source: 'unembedded',
      );
    }
    final merchants = await _database.select(_database.merchants).get();
    Merchant? best;
    var bestScore = -1.0;
    for (final merchant in merchants) {
      final stored = _decode(merchant.embedding);
      if (stored == null) continue;
      final score = cosineSimilarity(embedding, stored);
      if (score > bestScore) {
        bestScore = score;
        best = merchant;
      }
    }
    final now = DateTime.now().toUtc();
    if (best != null && bestScore >= reviewThreshold) {
      final learned = bestScore >= autoLinkThreshold;
      await _database.into(_database.merchantAliases).insertOnConflictUpdate(
            MerchantAliasesCompanion.insert(
              alias: alias,
              merchantId: best.id,
              source: learned ? 'learned' : 'similarity',
              confidence: bestScore,
            ),
          );
      return MerchantResolution(
        merchantId: best.id,
        canonicalName: best.canonicalName,
        embedding: _decode(best.embedding),
        confidence: bestScore,
        source: learned ? 'learned' : 'similarity',
        needsReview: !learned,
      );
    }

    final id = 'merchant_$alias';
    await _database.into(_database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: id,
            canonicalName: raw.trim(),
            embedding: Value(_encode(embedding)),
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await _database.into(_database.merchantAliases).insertOnConflictUpdate(
          MerchantAliasesCompanion.insert(
            alias: alias,
            merchantId: id,
            source: 'new',
            confidence: 1,
          ),
        );
    return MerchantResolution(
      merchantId: id,
      canonicalName: raw.trim(),
      embedding: embedding,
      confidence: 1,
      source: 'new',
    );
  }

  static String normalizeAlias(String value) => PayeeIdentityKey.normalize(value);

  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.isEmpty || a.length != b.length) return -1;
    var dot = 0.0;
    var aNorm = 0.0;
    var bNorm = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aNorm += a[i] * a[i];
      bNorm += b[i] * b[i];
    }
    if (aNorm == 0 || bNorm == 0) return -1;
    return dot / (sqrt(aNorm) * sqrt(bNorm));
  }

  static Uint8List _encode(Float32List value) =>
      value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);

  static Float32List? _decode(Uint8List? value) {
    if (value == null ||
        value.lengthInBytes % Float32List.bytesPerElement != 0) {
      return null;
    }
    return Float32List.view(
      value.buffer,
      value.offsetInBytes,
      value.lengthInBytes ~/ 4,
    );
  }
}

final merchantResolverProvider = Provider.family<MerchantResolver, AppDatabase>(
  (ref, database) => MerchantResolver(database, ref.watch(embedderProvider)),
);
