import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/enrichment/payee_identity_key.dart';
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
  int calls = 0;

  @override
  Future<Float32List?> embed(String text) async {
    calls++;
    return vectors[text];
  }

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

    test('embedder unavailable still creates a stable exact identity',
        () async {
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({'SWIGGYINSTAMART': null}),
      );

      final result =
          await resolver.resolve(_record(merchantRaw: 'Swiggy Instamart'));

      expect(result.confidence, 1);
      expect(result.source, 'new');
      expect(result.canonicalName, 'Swiggy Instamart');
      expect(result.merchantId, 'merchant_SWIGGYINSTAMART');
      expect(await database.select(database.merchants).get(), hasLength(1));
    });

    test('cosine >= 0.92 only suggests and never assigns or aliases', () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({
          'SWIGGYINSTAMART': _vec([1, 0]),
        }),
      );

      final result =
          await resolver.resolve(_record(merchantRaw: 'Swiggy Instamart'));

      expect(result.merchantId, isNull);
      expect(result.suggestedMerchantId, 'merchant_swiggy');
      expect(result.confidence, closeTo(1.0, 1e-9));
      expect(result.source, 'suggestion');
      expect(result.needsReview, isTrue);
      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test('0.75 <= cosine < 0.92 suggests without changing identity', () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      // cosine([1,0], [0.8,0.6]) == 0.8
      final resolver = MerchantResolver(
        database,
        _FakeEmbedder({
          'SWIGGYX': _vec([0.8, 0.6]),
        }),
      );

      final result = await resolver.resolve(_record(merchantRaw: 'SwiggyX'));

      expect(result.merchantId, isNull);
      expect(result.suggestedMerchantId, 'merchant_swiggy');
      // Float32 storage round-trip loses precision beyond ~1e-7.
      expect(result.confidence, closeTo(0.8, 1e-6));
      expect(result.source, 'suggestion');
      expect(result.needsReview, isTrue);
      expect(await database.select(database.merchantAliases).get(), isEmpty);

      final repeated = await resolver.resolve(_record(merchantRaw: 'SwiggyX'));
      expect(repeated.confidence, closeTo(0.8, 1e-6));
      expect(repeated.source, 'suggestion');
      expect(repeated.needsReview, isTrue);
      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test('legacy fuzzy aliases resolve as suggestions without being rewritten',
        () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      for (final source in ['learned', 'similarity']) {
        final alias = source == 'learned' ? 'SWIGGYX' : 'SWIGGYY';
        await database.into(database.merchantAliases).insertOnConflictUpdate(
              MerchantAliasesCompanion.insert(
                alias: alias,
                merchantId: 'merchant_swiggy',
                source: source,
                confidence: 0.99,
              ),
            );
        final result = await MerchantResolver(
          database,
          const NoopEmbedder(),
        ).resolve(_record(merchantRaw: alias));

        expect(result.merchantId, isNull);
        expect(result.suggestedMerchantId, 'merchant_swiggy');
        expect(result.source, 'suggestion');
        final stored = await (database.select(database.merchantAliases)
              ..where((row) => row.alias.equals(alias)))
            .getSingle();
        expect(stored.source, source);
      }
    });

    test('decorated merchant names and matching VPA use one stable identity',
        () async {
      final resolver = MerchantResolver(database, const NoopEmbedder());
      final decorated = await resolver.resolve(
        _record(merchantRaw: 'UPI-SWIGGY', counterpartyVpa: 'swiggy@ybl'),
      );
      final plain = await resolver.resolve(_record(merchantRaw: 'SWIGGY'));
      final legalName = await resolver.resolve(
        _record(merchantRaw: 'Swiggy Ltd'),
      );
      final vpaAlias = await (database.select(database.merchantAliases)
            ..where((row) => row.alias.equals('SWIGGYYBL')))
          .getSingle();
      expect(vpaAlias.merchantId, decorated.merchantId);
      final vpaOnly = await resolver.resolve(
        _record(counterpartyVpa: 'swiggy@ybl'),
      );

      expect(
        {decorated.merchantId, plain.merchantId, legalName.merchantId},
        {'merchant_SWIGGY'},
      );
      expect(vpaOnly.merchantId, decorated.merchantId);
    });

    test('stores only the legacy name alias while looking up both name keys',
        () async {
      final resolver = MerchantResolver(database, const NoopEmbedder());

      final created = await resolver.resolve(
        _record(merchantRaw: 'UPI-SWIGGY'),
      );

      final aliases = await database.select(database.merchantAliases).get();
      expect(aliases.map((row) => row.alias), contains('UPISWIGGY'));
      expect(aliases.map((row) => row.alias), isNot(contains('SWIGGY')));
      expect(created.merchantId, 'merchant_SWIGGY');
    });

    test('PSP remains part of VPA identity', () async {
      final resolver = MerchantResolver(database, const NoopEmbedder());
      final ybl = await resolver.resolve(_record(counterpartyVpa: 'ravi@ybl'));
      final axis = await resolver.resolve(
        _record(counterpartyVpa: 'ravi@okaxis'),
      );

      expect(ybl.merchantId, isNot(axis.merchantId));
    });

    test('VPA user alias outranks text and phone VPAs still resolve aliases',
        () async {
      await seedMerchant('merchant_user', 'Groceries', _vec([1, 0]));
      for (final alias in ['RAVIYBL', '9876543210YBL', 'OTHERSHOP']) {
        await database.into(database.merchantAliases).insertOnConflictUpdate(
              MerchantAliasesCompanion.insert(
                alias: alias,
                merchantId: 'merchant_user',
                source: 'user',
                confidence: 1,
              ),
            );
      }
      final resolver = MerchantResolver(database, const NoopEmbedder());

      final named = await resolver.resolve(
        _record(merchantRaw: 'Other Shop', counterpartyVpa: 'ravi@ybl'),
      );
      final phone = await resolver.resolve(
        _record(counterpartyVpa: '9876543210@ybl'),
      );
      final nameOnly = await resolver.resolve(
        _record(merchantRaw: 'Other Shop', counterpartyVpa: 'unknown@okaxis'),
      );

      expect(named.merchantId, 'merchant_user');
      expect(named.source, 'user');
      expect(phone.merchantId, 'merchant_user');
      expect(phone.source, 'user');
      expect(nameOnly.merchantId, 'merchant_user');
      expect(nameOnly.source, 'user');
    });

    test('legacy user alias uses the stored pre-R2 normalization', () async {
      await seedMerchant('merchant_food', 'Food delivery', _vec([1, 0]));
      await database.into(database.merchantAliases).insert(
            MerchantAliasesCompanion.insert(
              alias: 'UPISWIGGY',
              merchantId: 'merchant_food',
              source: 'user',
              confidence: 1,
            ),
          );

      final result = await MerchantResolver(
        database,
        const NoopEmbedder(),
      ).resolve(_record(merchantRaw: 'UPI-SWIGGY'));

      expect(result.merchantId, 'merchant_food');
      expect(result.source, 'user');
      expect(await database.select(database.merchants).get(), hasLength(1));
    });

    test('finds a pre-R2 merchant id without creating an R2 duplicate',
        () async {
      await seedMerchant(
        'merchant_UPISWIGGY',
        'UPI-SWIGGY',
        _vec([1, 0]),
      );

      final result = await MerchantResolver(
        database,
        const NoopEmbedder(),
      ).resolve(_record(merchantRaw: 'UPI-SWIGGY'));

      expect(result.merchantId, 'merchant_UPISWIGGY');
      expect(await database.select(database.merchants).get(), hasLength(1));
    });

    test('legacy user alias resolves without writing the new name key',
        () async {
      await seedMerchant('merchant_food', 'Food delivery', _vec([1, 0]));
      await database.into(database.merchantAliases).insert(
            MerchantAliasesCompanion.insert(
              alias: 'UPISWIGGY',
              merchantId: 'merchant_food',
              source: 'user',
              confidence: 1,
            ),
          );
      final resolver = MerchantResolver(database, const NoopEmbedder());

      final decorated = await resolver.resolve(
        _record(merchantRaw: 'UPI-SWIGGY'),
      );
      final plain = await resolver.resolve(_record(merchantRaw: 'SWIGGY'));

      expect(decorated.merchantId, 'merchant_food');
      expect(plain.merchantId, 'merchant_SWIGGY');
      expect(await database.select(database.merchants).get(), hasLength(2));
      final aliases = await database.select(database.merchantAliases).get();
      expect(
        aliases.singleWhere((row) => row.alias == 'UPISWIGGY').merchantId,
        'merchant_food',
      );
    });

    test('phone VPA is never auto-stored as an alias', () async {
      final resolver = MerchantResolver(
        database,
        const NoopEmbedder(),
      );
      final record = _record(
        merchantRaw: 'Local Shop',
        counterpartyVpa: '9876543210@ybl',
      );
      final result = await resolver.resolve(record);
      await resolver.resolve(record);

      expect(result.source, 'new');
      final aliases = await database.select(database.merchantAliases).get();
      expect(aliases.map((row) => row.alias), contains('LOCALSHOP'));
      expect(aliases.map((row) => row.alias), isNot(contains('9876543210YBL')));
    });

    test('all-digit UPI local parts of seven or more digits stay private',
        () async {
      final result = await MerchantResolver(
        database,
        const NoopEmbedder(),
      ).resolve(_record(counterpartyVpa: '1234567@ybl'));

      expect(result.merchantId, isNull);
      expect(result.canonicalName, 'P2P Transfer');
      expect(await database.select(database.merchants).get(), isEmpty);
      expect(await database.select(database.merchantAliases).get(), isEmpty);
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

    test('import run reuses its merchant snapshot without caching suggestions',
        () async {
      await seedMerchant('merchant_swiggy', 'Swiggy', _vec([1, 0]));
      final embedder = _FakeEmbedder({
        'SWIGGYX': _vec([1, 0]),
      });
      final resolver = MerchantResolver(database, embedder);
      final run = await resolver.beginImportRun();

      final first = await resolver.resolve(
        _record(merchantRaw: 'SwiggyX'),
        run: run,
      );
      final second = await resolver.resolve(
        _record(merchantRaw: 'SwiggyX'),
        run: run,
      );

      expect(first.suggestedMerchantId, 'merchant_swiggy');
      expect(second.suggestedMerchantId, 'merchant_swiggy');
      expect(embedder.calls, 2);
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
      expect(result.merchantId, 'merchant_FRIENDUPI');
      expect(result.source, 'new');
    });
  });

  group('normalizeAlias', () {
    test('uppercases and strips non-alphanumeric characters', () {
      expect(
        MerchantResolver.normalizeAlias('Swiggy Instamart!'),
        'SWIGGYINSTAMART',
      );
      expect(MerchantResolver.normalizeAlias('  hdfc-bank_09  '), 'HDFCBANK09');
      expect(MerchantResolver.normalizeAlias('UPI-SWIGGY'), 'UPISWIGGY');
    });
  });

  group('PayeeIdentityKey', () {
    test('normalizes decorated fixture merchant strings conservatively', () {
      final fixtures = {
        'SWIGGY': 'SWIGGY',
        'AMAZON INDIA': 'AMAZONINDIA',
        'Coffee Shop': 'COFFEESHOP',
        'Vivek store': 'VIVEKSTORE',
        'BLINKIT': 'BLINKIT',
        'UPI-SWIGGY': 'SWIGGY',
        'UPI/SWIGGY': 'SWIGGY',
        'VPS*SWIGGY': 'SWIGGY',
        'POS SWIGGY': 'SWIGGY',
        'Swiggy Ltd': 'SWIGGY',
        'CORN 4471': 'CORN4471',
        'Blink Commerce P': 'BLINKCOMMERCEP',
      };
      for (final entry in fixtures.entries) {
        expect(
          PayeeKey.parse(name: entry.key).nameKey,
          entry.value,
          reason: entry.key,
        );
      }
      expect(PayeeKey.parse(vpa: 'ravi@ybl').vpaKey, 'RAVIYBL');
      expect(
        PayeeKey.parse(vpa: 'ravi@okaxis').vpaKey,
        'RAVIOKAXIS',
      );
    });
  });

  test('PayeeKey.keyFor chooses VPA keys and stored-contract name keys', () {
    expect(PayeeKey.keyFor('UPI-SWIGGY'), 'UPISWIGGY');
    expect(PayeeKey.keyFor('swiggy@ybl'), 'SWIGGYYBL');
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
