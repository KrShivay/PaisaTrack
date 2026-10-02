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
    this.suggestedMerchantId,
    required this.confidence,
    required this.source,
    this.needsReview = false,
  });

  final String? merchantId;
  final String? canonicalName;
  final Float32List? embedding;
  final String? suggestedMerchantId;
  final double confidence;
  final String source;
  final bool needsReview;
}

/// Merchant snapshot shared by one history/catch-up run.
class MerchantResolutionRun {
  MerchantResolutionRun(this.merchants, this.byNameKey);

  final List<Merchant> merchants;
  final Map<String, Merchant> byNameKey;

  MerchantResolutionRun stage() =>
      MerchantResolutionRun(List.of(merchants), Map.of(byNameKey));

  void commit(MerchantResolutionRun staged) {
    final knownIds = merchants.map((merchant) => merchant.id).toSet();
    for (final merchant in staged.merchants) {
      if (knownIds.add(merchant.id)) merchants.add(merchant);
    }
    for (final entry in staged.byNameKey.entries) {
      byNameKey.putIfAbsent(entry.key, () => entry.value);
    }
  }
}

/// Resolves explicit payee identity first; embeddings can only suggest review.
///
/// Live resolution uses deterministic cosine search for review suggestions.
/// History and catch-up runs pass one merchant snapshot across all pages.
class MerchantResolver {
  MerchantResolver(this._database, this._embedder);

  static const reviewThreshold = .75;

  final AppDatabase _database;
  final Embedder _embedder;

  Future<MerchantResolutionRun> beginImportRun() async {
    final merchants = await _database.select(_database.merchants).get();
    final byNameKey = <String, Merchant>{};
    for (final merchant in merchants) {
      final parsed = PayeeKey.parse(name: merchant.canonicalName);
      for (final key in {
        parsed.nameKey,
        PayeeKey.keyFor(merchant.canonicalName),
      }) {
        if (key.isNotEmpty) byNameKey.putIfAbsent(key, () => merchant);
      }
    }
    return MerchantResolutionRun(merchants, byNameKey);
  }

  Future<MerchantResolution> resolve(
    NormalizedTransactionRecord record, {
    MerchantResolutionRun? run,
    bool allowSuggestions = true,
  }) async {
    final counterparty = const CounterpartyKeyParser().parse(
      vpa: record.counterpartyVpa,
      merchantRaw: record.merchantRaw,
    );

    final keys = PayeeKey.parse(
      name: record.merchantRaw,
      vpa: record.counterpartyVpa,
    );
    final raw = record.merchantRaw?.trim();
    if ((raw == null || raw.isEmpty) && keys.vpaKey.isEmpty) {
      return const MerchantResolution(confidence: 0, source: 'none');
    }
    final vpaAlias = await _findAlias(keys.vpaKey, userOnly: true);
    if (vpaAlias != null) return vpaAlias;
    if (raw != null) {
      for (final key in _nameKeys(raw, keys.nameKey)) {
        final alias = await _findAlias(key, userOnly: true);
        if (alias != null) {
          await _recordResolvedNameAliases(raw, alias.merchantId);
          return alias;
        }
      }
    }

    final exactName = raw == null || keys.nameKey.isEmpty
        ? null
        : await _findMerchantByNameKeys(
            _nameKeys(raw, keys.nameKey),
            run: run,
          );
    if (exactName != null) {
      await _recordResolvedNameAliases(raw!, exactName.id);
      if (keys.vpaKey.isNotEmpty && !_isPhoneVpa(record.counterpartyVpa)) {
        await _recordAlias(keys.vpaKey, exactName.id, 'exact');
      }
      return _resolved(exactName, 'exact');
    }

    // Preserve exact legacy aliases after new user aliases and canonical names.
    for (final alias in [
      keys.vpaKey,
      if (raw != null) ..._nameKeys(raw, keys.nameKey),
    ]) {
      final result = await _findAlias(alias);
      if (result != null) {
        if (raw != null && result.merchantId != null) {
          await _recordResolvedNameAliases(
            raw,
            result.merchantId!,
          );
        }
        return result;
      }
    }

    // Phone based VPA identities are private; a known alias may resolve above,
    // but an unknown phone identity must never create a merchant.
    if (record.merchantRaw == null &&
        (counterparty.kind == CounterpartyKind.person ||
            counterparty.kind == CounterpartyKind.self)) {
      return MerchantResolution(
        canonicalName: _isPhoneVpa(record.counterpartyVpa)
            ? 'P2P Transfer'
            : record.counterpartyVpa ??
                counterparty.displayName ??
                'P2P Transfer',
        confidence: 1,
        source: 'counterparty_person',
      );
    }

    final identityKey =
        raw != null && keys.nameKey.isNotEmpty ? keys.nameKey : keys.vpaKey;
    final displayName = raw?.isNotEmpty == true
        ? raw!
        : record.counterpartyVpa?.trim() ??
            counterparty.inferredName ??
            identityKey;
    final phoneVpa = _isPhoneVpa(record.counterpartyVpa);
    if (!allowSuggestions) {
      return _createMerchant(
        identityKey,
        displayName,
        null,
        phoneVpa ? '' : keys.vpaKey,
        rawName: raw,
        nameKey: keys.nameKey,
        run: run,
      );
    }
    final embedding = await _embedder.embed(identityKey);
    if (embedding == null) {
      return _createMerchant(
        identityKey,
        displayName,
        null,
        phoneVpa ? '' : keys.vpaKey,
        rawName: raw,
        nameKey: keys.nameKey,
        run: run,
      );
    }
    final merchants =
        run?.merchants ?? await _database.select(_database.merchants).get();
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
    if (best != null && bestScore >= reviewThreshold) {
      final suggestion = MerchantResolution(
        canonicalName: best.canonicalName,
        embedding: _decode(best.embedding),
        suggestedMerchantId: best.id,
        confidence: bestScore,
        source: 'suggestion',
        needsReview: true,
      );
      return suggestion;
    }

    return _createMerchant(
      identityKey,
      displayName,
      embedding,
      phoneVpa ? '' : keys.vpaKey,
      rawName: raw,
      nameKey: keys.nameKey,
      run: run,
    );
  }

  Future<MerchantResolution?> _findAlias(
    String alias, {
    bool userOnly = false,
  }) async {
    if (alias.isEmpty) return null;
    final aliasRow = await (_database.select(_database.merchantAliases)
          ..where((row) => row.alias.equals(alias)))
        .getSingleOrNull();
    if (aliasRow == null || (userOnly && aliasRow.source != 'user')) {
      return null;
    }
    final merchant = await (_database.select(_database.merchants)
          ..where((row) => row.id.equals(aliasRow.merchantId)))
        .getSingleOrNull();
    if (merchant == null) return null;
    if (aliasRow.source == 'learned' || aliasRow.source == 'similarity') {
      return MerchantResolution(
        canonicalName: merchant.canonicalName,
        embedding: _decode(merchant.embedding),
        suggestedMerchantId: merchant.id,
        confidence: aliasRow.confidence,
        source: 'suggestion',
        needsReview: true,
      );
    }
    return _resolved(merchant, aliasRow.source);
  }

  Future<Merchant?> _findMerchantByNameKeys(
    List<String> nameKeys, {
    MerchantResolutionRun? run,
  }) async {
    if (run != null) {
      for (final key in nameKeys) {
        final merchant = run.byNameKey[key];
        if (merchant != null) return merchant;
      }
      return null;
    }
    final merchants = await _database.select(_database.merchants).get();
    for (final merchant in merchants) {
      final parsed = PayeeKey.parse(name: merchant.canonicalName);
      if (nameKeys.contains(parsed.nameKey) ||
          nameKeys.contains(PayeeKey.keyFor(merchant.canonicalName))) {
        return merchant;
      }
    }
    return null;
  }

  MerchantResolution _resolved(Merchant merchant, String source) =>
      MerchantResolution(
        merchantId: merchant.id,
        canonicalName: merchant.userLabel ?? merchant.canonicalName,
        embedding: _decode(merchant.embedding),
        confidence: 1,
        source: source,
      );

  Future<void> _recordAlias(String alias, String id, String source) async {
    if (alias.isEmpty) return;
    await _database.into(_database.merchantAliases).insertOnConflictUpdate(
          MerchantAliasesCompanion.insert(
            alias: alias,
            merchantId: id,
            source: source,
            confidence: 1,
          ),
        );
  }

  Future<void> _recordResolvedNameAliases(
    String raw,
    String? merchantId,
  ) async {
    if (merchantId == null) return;
    final storedKey = PayeeKey.keyFor(raw);
    await _recordAliasIfAvailable(storedKey, merchantId, 'exact');
  }

  Future<void> _recordAliasIfAvailable(
    String alias,
    String merchantId,
    String source,
  ) async {
    if (alias.isEmpty) return;
    final existing = await (_database.select(_database.merchantAliases)
          ..where((row) => row.alias.equals(alias)))
        .getSingleOrNull();
    if (existing == null) {
      await _recordAlias(alias, merchantId, source);
    } else if (existing.merchantId == merchantId && existing.source != 'user') {
      await _recordAlias(alias, merchantId, source);
    }
  }

  static List<String> _nameKeys(String raw, String nameKey) => [
        if (nameKey.isNotEmpty) nameKey,
        if (PayeeKey.keyFor(raw).isNotEmpty && PayeeKey.keyFor(raw) != nameKey)
          PayeeKey.keyFor(raw),
      ];

  static bool _isPhoneVpa(String? value) {
    if (value == null || !value.contains('@')) return false;
    final local = value.substring(0, value.lastIndexOf('@')).trim();
    return RegExp(r'^\d{7,}$').hasMatch(local);
  }

  Future<MerchantResolution> _createMerchant(
    String identityKey,
    String displayName,
    Float32List? embedding,
    String vpaKey, {
    String? rawName,
    String? nameKey,
    MerchantResolutionRun? run,
  }) async {
    final now = DateTime.now().toUtc();
    final id = 'merchant_$identityKey';
    final storedNameKey =
        rawName == null ? identityKey : PayeeKey.keyFor(rawName);
    await _database.into(_database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: id,
            canonicalName: displayName,
            embedding: Value(embedding == null ? null : _encode(embedding)),
            firstSeen: now,
            lastSeen: now,
          ),
        );
    if (run != null) {
      final merchant = await (_database.select(_database.merchants)
            ..where((row) => row.id.equals(id)))
          .getSingle();
      run.merchants.add(merchant);
      run.byNameKey.putIfAbsent(identityKey, () => merchant);
      if (nameKey != null && nameKey.isNotEmpty) {
        run.byNameKey.putIfAbsent(nameKey, () => merchant);
      }
      if (storedNameKey.isNotEmpty) {
        run.byNameKey.putIfAbsent(storedNameKey, () => merchant);
      }
    }
    await _recordAliasIfAvailable(storedNameKey, id, 'new');
    if (vpaKey.isNotEmpty && vpaKey != identityKey) {
      await _recordAlias(vpaKey, id, 'new');
    }
    return MerchantResolution(
      merchantId: id,
      canonicalName: displayName,
      embedding: embedding,
      confidence: 1,
      source: 'new',
    );
  }

  static String normalizeAlias(String value) => PayeeKey.keyFor(value);

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
