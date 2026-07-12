import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

NormalizedTransactionRecord _record({
  String? merchantRaw,
  String? counterpartyVpa,
}) {
  return NormalizedTransactionRecord(
    amount: 449,
    direction: TransactionDirection.debit,
    channel: TransactionChannel.upi,
    merchantRaw: merchantRaw,
    counterpartyVpa: counterpartyVpa,
    accountHint: null,
    balanceAfter: null,
    refId: null,
    ts: DateTime.utc(2026, 7, 7, 10),
    parseSource: ParseSource.template,
    parseConfidence: 0.97,
  );
}

Float32List _vec(List<double> values) => Float32List.fromList(values);

Uint8List _encode(Float32List value) =>
    value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);

/// Returns a fixed vector for each input text, or null when the text isn't
/// registered — lets tests force each similarity band deterministically.
class _FakeEmbedder implements Embedder {
  _FakeEmbedder(this.vectors);
  final Map<String, Float32List?> vectors;

  @override
  Future<Float32List?> embed(String text) async => vectors[text];

  @override
  Future<bool> isModelAvailable() async => true;

  @override
  Future<bool> downloadModel() async => true;

  @override
  Future<bool> deleteModel() async => true;
}

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedMerchant(String id, String name, Float32List embedding) {
    final now = DateTime.utc(2026, 7, 1);
    return database.into(database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: id,
            canonicalName: name,
            embedding: Value(_encode(embedding)),
            firstSeen: now,
            lastSeen: now,
          ),
        );
  }

  group('resolve', () {
    test('no merchant text or counterparty -> confidence 0, source none',
        () async {
      final resolver = MerchantResolver(database, const NoopEmbedder());
      final result = await resolver.resolve(_record());
      expect(result.confidence, 0);
      expect(result.source, 'none');
      expect(result.merchantId, isNull);
    });

    test('exact alias lookup wins at confidence 1.0', () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0, 0]));
      await database.into(database.merchantAliases).insertOnConflictUpdate(
            MerchantAliasesCompanion.insert(
              alias: MerchantResolver.normalizeAlias('Swiggy Instamart'),
              merchantId: 'merchant_swiggy',
              source: 'device',
              confidence: 1,
            ),
          );
      final resolver = MerchantResolver(database, const NoopEmbedder());

      final result =
          await resolver.resolve(_record(merchantRaw: 'Swiggy Instamart'));

      expect(result.merchantId, 'merchant_swiggy');
      expect(result.canonicalName, 'Swiggy');
      expect(result.confidence, 1.0);
      expect(result.source, 'device');
      expect(result.needsReview, isFalse);
    });

    test('embedder unavailable -> unembedded fallback, no DB writes', () async {
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({'SWIGGYINSTAMART': null}),
      );

      final result =
          await resolver.resolve(_record(merchantRaw: 'Swiggy Instamart'));

      expect(result.confidence, 0);
      expect(result.source, 'unembedded');
      expect(result.canonicalName, 'Swiggy Instamart');
      expect(await database.select(database.merchants).get(), isEmpty);
    });

    test('cosine >= 0.92 auto-links and writes a learned alias', () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({
          'SWIGGYINSTAMART': _vec([1, 0]),
        }),
      );

      final result =
          await resolver.resolve(_record(merchantRaw: 'Swiggy Instamart'));

      expect(result.merchantId, 'merchant_swiggy');
      expect(result.confidence, closeTo(1.0, 1e-9));
      expect(result.source, 'learned');
      expect(result.needsReview, isFalse);

      final alias = await (database.select(database.merchantAliases)
            ..where((row) => row.alias.equals('SWIGGYINSTAMART')))
          .getSingle();
      expect(alias.merchantId, 'merchant_swiggy');
      expect(alias.source, 'learned');
    });

    test('0.75 <= cosine < 0.92 links with needs_review, source similarity',
        () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      // cosine([1,0], [0.8,0.6]) == 0.8
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({
          'SWIGGYX': _vec([0.8, 0.6]),
        }),
      );

      final result = await resolver.resolve(_record(merchantRaw: 'SwiggyX'));

      expect(result.merchantId, 'merchant_swiggy');
      // Float32 storage round-trip loses precision beyond ~1e-7.
      expect(result.confidence, closeTo(0.8, 1e-6));
      expect(result.source, 'similarity');
      expect(result.needsReview, isTrue);

      final alias = await (database.select(database.merchantAliases)
            ..where((row) => row.alias.equals('SWIGGYX')))
          .getSingle();
      expect(alias.source, 'similarity');

      final repeated = await resolver.resolve(_record(merchantRaw: 'SwiggyX'));
      expect(repeated.confidence, closeTo(0.8, 1e-6));
      expect(repeated.source, 'similarity');
      expect(repeated.needsReview, isTrue);
    });

    test('cosine < 0.75 creates and embeds a new merchant', () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      // cosine([1,0], [0,1]) == 0
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({
          'NEWVENDOR': _vec([0, 1]),
        }),
      );

      final result = await resolver.resolve(_record(merchantRaw: 'NewVendor'));

      expect(result.confidence, 1);
      expect(result.source, 'new');
      expect(result.canonicalName, 'NewVendor');
      expect(result.merchantId, isNotNull);

      final merchants = await database.select(database.merchants).get();
      expect(merchants, hasLength(2));
      final created = merchants.singleWhere((m) => m.id == result.merchantId);
      expect(created.canonicalName, 'NewVendor');
      expect(created.embedding, isNotNull);
    });

    test('falls back to the counterparty VPA when merchant text is absent',
        () async {
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({'FRIENDUPI': null}),
      );

      final result =
          await resolver.resolve(_record(counterpartyVpa: 'friend@upi'));

      expect(result.canonicalName, 'friend@upi');
      expect(result.source, 'unembedded');
    });
  });

  group('normalizeAlias', () {
    test('uppercases and strips non-alphanumeric characters', () {
      expect(
        MerchantResolver.normalizeAlias('Swiggy Instamart!'),
        'SWIGGYINSTAMART',
      );
      expect(MerchantResolver.normalizeAlias('  hdfc-bank_09  '), 'HDFCBANK09');
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors score 1.0', () {
      expect(
        MerchantResolver.cosineSimilarity(_vec([1, 2, 3]), _vec([1, 2, 3])),
        closeTo(1.0, 1e-9),
      );
    });

    test('orthogonal vectors score 0.0', () {
      expect(
        MerchantResolver.cosineSimilarity(_vec([1, 0]), _vec([0, 1])),
        closeTo(0.0, 1e-9),
      );
    });

    test('mismatched length or empty vectors score -1', () {
      expect(MerchantResolver.cosineSimilarity(_vec([]), _vec([])), -1);
      expect(
        MerchantResolver.cosineSimilarity(_vec([1, 2]), _vec([1, 2, 3])),
        -1,
      );
    });

    test('a zero vector scores -1 (undefined direction)', () {
      expect(
        MerchantResolver.cosineSimilarity(_vec([0, 0]), _vec([1, 1])),
        -1,
      );
    });
  });
}
