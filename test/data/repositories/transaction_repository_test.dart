import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

Future<void> _seedCategories(AppDatabase database) async {
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'other',
          name: 'Other',
          icon: 'category',
          isSpending: true,
          sortOrder: 1,
          isUserCreated: false,
        ),
      );
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'food_dining',
          name: 'Food & Dining',
          icon: 'restaurant',
          isSpending: true,
          sortOrder: 2,
          isUserCreated: false,
        ),
      );
}

Future<String> _seedMerchant(AppDatabase database, String canonicalName) {
  final id = 'merchant_${canonicalName.toLowerCase()}';
  final now = DateTime.utc(2026, 7, 1);
  return database
      .into(database.merchants)
      .insertOnConflictUpdate(
        MerchantsCompanion.insert(
          id: id,
          canonicalName: canonicalName,
          firstSeen: now,
          lastSeen: now,
        ),
      )
      .then((_) => id);
}

Future<void> _insertTxn(
  AppDatabase database, {
  required String id,
  String? merchantId,
  String? merchantRaw,
  String status = 'asked',
  String categoryId = 'other',
}) {
  final now = DateTime.utc(2026, 7, 8, 9);
  return database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: now.millisecondsSinceEpoch,
          amount: 250,
          direction: 'debit',
          channel: 'upi',
          merchantId: Value(merchantId),
          merchantRaw: Value(merchantRaw),
          categoryId: Value(categoryId),
          parseSource: 'template',
          confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
          status: status,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await _seedCategories(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('correctWithRule', () {
    test('writes a learned merchant alias when the transaction is already '
        'resolver-linked', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_1',
        merchantId: merchantId,
        merchantRaw: 'SWIGGY *ORDER 991',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_1',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      final alias = await (database.select(database.merchantAliases)
            ..where((row) => row.alias.equals('SWIGGYORDER991')))
          .getSingle();
      expect(alias.merchantId, merchantId);
      expect(alias.source, 'learned');
      expect(alias.confidence, 1);
    });

    test('does not write an alias when the transaction has no resolved '
        'merchant', () async {
      await _insertTxn(
        database,
        id: 'txn_2',
        merchantId: null,
        merchantRaw: 'SWIGGY *ORDER 991',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_2',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test('does not write an alias when merchantRaw is absent', () async {
      final merchantId = await _seedMerchant(database, 'Friend');
      await _insertTxn(
        database,
        id: 'txn_3',
        merchantId: merchantId,
        merchantRaw: null,
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_3',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test('alias write commits atomically with the rule, feedback, and status '
        'update', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_4',
        merchantId: merchantId,
        merchantRaw: 'Swiggy Instamart',
      );

      final feedbackCount =
          await TransactionRepository(database).correctWithRule(
        txnId: 'txn_4',
        categoryId: 'food_dining',
        context: 'weekly_review',
      );

      expect(feedbackCount, greaterThan(0));
      final txn = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_4')))
          .getSingle();
      expect(txn.categoryId, 'food_dining');
      expect(txn.status, 'confirmed');
      final rules = await database.select(database.rules).get();
      expect(rules, hasLength(1));
      final alias = await database.select(database.merchantAliases).get();
      expect(alias, hasLength(1));
      expect(alias.single.merchantId, merchantId);
    });

    test('a repeat correction updates the same alias row rather than '
        'duplicating it', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_5',
        merchantId: merchantId,
        merchantRaw: 'Swiggy Instamart',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_5',
        categoryId: 'food_dining',
        context: 'ask_now',
      );
      // Second correction on the same normalized alias must upsert, not
      // insert a duplicate primary-key row.
      await _insertTxn(
        database,
        id: 'txn_6',
        merchantId: merchantId,
        merchantRaw: 'swiggy instamart',
        status: 'asked',
      );
      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_6',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      final aliases = await database.select(database.merchantAliases).get();
      expect(aliases, hasLength(1));
    });
  });
}
