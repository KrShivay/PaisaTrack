import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/category_correction.dart';
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
  String? counterpartyVpa,
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
          counterpartyVpa: Value(counterpartyVpa),
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
    test(
        'writes a learned merchant alias when the transaction is already '
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

    test(
        'does not write an alias when the transaction has no resolved '
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

    test(
        'alias write commits atomically with the rule, feedback, and status '
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

    test(
        'a repeat correction updates the same alias row rather than '
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

  group('correctCategory scopes', () {
    test('this transaction changes no history and creates no rule', () async {
      await _insertTxn(
        database,
        id: 'current',
        merchantRaw: 'Bookstore',
      );
      await _insertTxn(
        database,
        id: 'history',
        merchantRaw: 'Bookstore',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.thisTransaction,
        context: 'detail_edit',
      );

      expect(result.affectedTransactionCount, 1);
      expect(result.ruleCreated, isFalse);
      final rows = await database.select(database.transactions).get();
      expect(
        rows.singleWhere((row) => row.id == 'current').categoryId,
        'food_dining',
      );
      expect(
        rows.singleWhere((row) => row.id == 'history').categoryId,
        'other',
      );
      expect(await database.select(database.rules).get(), isEmpty);
    });

    test('future scope creates a rule without rewriting history', () async {
      await _insertTxn(
        database,
        id: 'current',
        merchantRaw: 'Bookstore',
      );
      await _insertTxn(
        database,
        id: 'history',
        merchantRaw: 'Bookstore',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.futureMatching,
        context: 'batch_review',
      );

      expect(result.ruleCreated, isTrue);
      expect(result.affectedTransactionCount, 1);
      expect(await database.select(database.rules).get(), hasLength(1));
      final history = await (database.select(database.transactions)
            ..where((row) => row.id.equals('history')))
          .getSingle();
      expect(history.categoryId, 'other');
    });

    test('existing and future scope updates normalized matching history',
        () async {
      await _insertTxn(
        database,
        id: 'current',
        counterpartyVpa: 'bookstore@ybl',
      );
      await _insertTxn(
        database,
        id: 'matching_history',
        counterpartyVpa: 'BOOKSTORE@YBL',
      );
      await _insertTxn(
        database,
        id: 'other_history',
        counterpartyVpa: 'other@ybl',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );

      expect(result.affectedTransactionCount, 2);
      expect(result.ruleCreated, isTrue);
      final rows = await database.select(database.transactions).get();
      expect(
        rows
            .where((row) => row.id != 'other_history')
            .every((row) => row.categoryId == 'food_dining'),
        isTrue,
      );
      expect(
        rows.singleWhere((row) => row.id == 'other_history').categoryId,
        'other',
      );
    });

    test('matching group updates only explicit ids and creates no rule',
        () async {
      for (final id in ['one', 'two', 'three']) {
        await _insertTxn(database, id: id, merchantRaw: 'Bookstore');
      }

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'one',
        categoryId: 'food_dining',
        scope: CorrectionScope.matchingGroup,
        matchingTxnIds: const {'one', 'two'},
        context: 'batch_review',
      );

      expect(result.affectedTransactionCount, 2);
      expect(result.ruleCreated, isFalse);
      final rows = await database.select(database.transactions).get();
      expect(rows.singleWhere((row) => row.id == 'three').categoryId, 'other');
      expect(await database.select(database.rules).get(), isEmpty);
    });
  });
}
