import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

class _FakeEmbedder implements Embedder {
  @override
  Future<Float32List?> embed(String text) async => null;

  @override
  Future<bool> isModelAvailable() async => true;

  @override
  Future<bool> downloadModel() async => true;

  @override
  Future<bool> deleteModel() async => true;
}

void main() {
  late AppDatabase database;
  late MerchantResolver resolver;
  late Categorizer categorizer;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    resolver = MerchantResolver(database, _FakeEmbedder());
    categorizer = Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap.fromJson('{}'),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('P2P payment creates no merchant row and is not auto-filed as transfers',
      () async {
    final p2pRecord = NormalizedTransactionRecord(
      amount: 500.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: null,
      counterpartyVpa: '9876543210@paytm',
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 7, 10),
      parseSource: ParseSource.generic,
      parseConfidence: 0.9,
    );

    final resolution = await resolver.resolve(p2pRecord);
    expect(resolution.merchantId, isNull);
    expect(resolution.needsReview, isFalse);

    // ADR 0011: a personal VPA alone does not prove a non-spending transfer
    // (shopkeepers use personal VPAs), so P2P falls back to review-able
    // `other` instead of being silently removed from spending as transfers.
    final categorization = await categorizer.categorize(p2pRecord);
    expect(categorization.categoryId, isNot('transfers'));
    expect(categorization.source, 'fallback');

    final merchants = await database.select(database.merchants).get();
    expect(merchants, isEmpty);
  });
}
