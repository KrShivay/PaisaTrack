import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/analytics/financial_eligibility.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dashboard SQL aggregates match the product review corpus contract',
      () async {
    final corpusFile = File('test/fixtures/product_review/corpus.json');
    final corpus =
        jsonDecode(await corpusFile.readAsString()) as Map<String, Object?>;
    expect(corpus['schemaVersion'], 1);

    final categories =
        (corpus['categories']! as List<Object?>).cast<Map<String, Object?>>();
    final fixtureTransactions =
        (corpus['transactions']! as List<Object?>).cast<Map<String, Object?>>();
    expect(fixtureTransactions, hasLength(20));
    final categoryRows = <String, Map<String, Object?>>{
      for (final category in categories) category['id']! as String: category,
    };
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    for (var index = 0; index < categories.length; index++) {
      final category = categories[index];
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: category['id']! as String,
              name: category['name']! as String,
              icon: 'corpus',
              isSpending: category['semantic'] != 'income_salary',
              sortOrder: index,
              isUserCreated: false,
            ),
          );
    }

    for (final fixture in fixtureTransactions) {
      final timestamp = DateTime.parse(fixture['ts']! as String);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: fixture['id']! as String,
              ts: timestamp.millisecondsSinceEpoch,
              amount: (fixture['amountPaise']! as num).toDouble() / 100,
              currencyCode: const Value('INR'),
              currencySymbol: const Value('₹'),
              direction: fixture['direction']! as String,
              channel: fixture['channel']! as String,
              categoryId: Value(fixture['categoryId'] as String?),
              duplicateOfTxnId: Value(fixture['duplicateOfTxnId'] as String?),
              ownedTransferId: Value(fixture['ownedTransferId'] as String?),
              isAnalyticsExcluded:
                  Value(fixture['isAnalyticsExcluded'] as bool? ?? false),
              isDeleted: Value(fixture['isDeleted'] as bool? ?? false),
              lifecycleState:
                  Value(fixture['lifecycleState'] as String? ?? 'settled'),
              status: fixture['status']! as String,
              parseSource: fixture['parseSource'] as String? ?? 'corpus',
              confidenceJson: '{}',
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
    }

    final storedRows = await database.select(database.transactions).get();
    expect(storedRows, hasLength(fixtureTransactions.length));

    final spendingTotalByCategory = <String, double>{};
    final eligibleDebits = storedRows.where((row) {
      final fixtureCategory = categoryRows[row.categoryId];
      final categoryIsSpending = fixtureCategory == null ||
          fixtureCategory['semantic'] != 'income_salary';
      return FinancialEligibility.includesSpendingDebit(
        row,
        categoryIsSpending: categoryIsSpending,
      );
    });
    for (final row in eligibleDebits) {
      final fixtureCategory = categoryRows[row.categoryId];
      final name = fixtureCategory?['name'] as String? ?? 'Uncategorised';
      spendingTotalByCategory.update(
        name,
        (total) => total + row.amount,
        ifAbsent: () => row.amount,
      );
    }
    final expectedDebitTotal = eligibleDebits.fold<double>(
      0,
      (total, row) => total + row.amount,
    );
    final eligibleCredits = storedRows.where(
      (row) =>
          !row.isDeleted &&
          row.duplicateOfTxnId == null &&
          !row.isAnalyticsExcluded &&
          row.ownedTransferId == null &&
          row.lifecycleState == 'settled' &&
          row.direction == 'credit',
    );
    final expectedCreditTotal = eligibleCredits.fold<double>(
      0,
      (total, row) => total + row.amount,
    );

    final start = DateTime.parse('2026-07-01T00:00:00+05:30');
    final end = DateTime.parse('2026-08-01T00:00:00+05:30');
    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: start,
        end: end,
        previousStart: DateTime.parse('2026-06-01T00:00:00+05:30'),
        previousEnd: start,
        trendStart: start,
        trendEnd: end,
        timeZoneOffset: const Duration(hours: 5, minutes: 30),
      ),
    );

    // Pin both the corpus-derived oracle and its SQL parity so a fixture edit
    // cannot silently redefine the expected spending contract.
    expect(expectedDebitTotal, 34852);
    expect(
      eligibleDebits.map((row) => row.id).toSet(),
      {
        'txn_manual_food_01',
        'txn_food_01',
        'txn_transport_01',
        'txn_rent_01',
        'txn_purchase_refund',
        'txn_reimbursed_expense',
        'txn_low_trust',
        'txn_same_timestamp_a',
        'txn_same_timestamp_b',
      },
    );
    expect(snapshot.debitTotal, expectedDebitTotal);
    expect(expectedCreditTotal, 127620);
    expect(
      eligibleCredits.map((row) => row.id).toSet(),
      {
        'txn_salary_01',
        'txn_cashback_01',
        'txn_refund',
        'txn_reimbursement',
      },
    );
    expect(snapshot.creditTotal, expectedCreditTotal);
    expect(snapshot.previousSpend, 0);
    expect(
      {
        for (final category in snapshot.categories)
          category.name: category.total,
      },
      spendingTotalByCategory,
    );
    expect(
      spendingTotalByCategory,
      {
        'Food': 5411,
        'Transport': 442,
        'Housing': 28000,
        'Uncategorized': 999,
      },
    );
    expect(snapshot.trendByMonth['2026-07'], expectedDebitTotal);

    final explicitlyExcludedRows = storedRows.where((row) {
      final fixtureCategory = categoryRows[row.categoryId];
      final categoryIsSpending = fixtureCategory == null ||
          fixtureCategory['semantic'] != 'income_salary';
      return !row.isDeleted &&
          row.duplicateOfTxnId == null &&
          row.lifecycleState == 'settled' &&
          row.direction == 'debit' &&
          categoryIsSpending &&
          (row.ownedTransferId != null || row.isAnalyticsExcluded);
    });
    final expectedExcludedTotal = explicitlyExcludedRows.fold<double>(
      0,
      (total, row) => total + row.amount,
    );
    expect(expectedExcludedTotal, 5500);
    expect(
      explicitlyExcludedRows.map((row) => row.id).toSet(),
      {'txn_transfer_out', 'txn_card_bill'},
    );
    expect(snapshot.excludedDebitTotal, expectedExcludedTotal);
    expect(snapshot.excludedDebitCount, explicitlyExcludedRows.length);
  });
}
