import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

// After T-158d, exclusion is driven solely by the flags that FinancialEligibility
// SQL actually honours (owned_transfer_id, is_analytics_excluded). Merchant-text
// heuristics for credit-card bills / ATM withdrawals were removed because they
// claimed exclusion for rows the SQL still counted. These tests pin that
// contract: an unflagged credit-card bill is counted and shows no banner; a
// flagged row is excluded and discloses the reason.

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<double> categorySum() async {
    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 7, 31),
        trendStart: DateTime.utc(2026, 7, 1),
        trendEnd: DateTime.utc(2026, 7, 31),
        previousStart: DateTime.utc(2026, 6, 1),
        previousEnd: DateTime.utc(2026, 6, 30),
      ),
    );
    return snapshot.categories.fold<double>(0.0, (acc, c) => acc + c.total);
  }

  test('credit card bill is counted unless flagged is_analytics_excluded',
      () async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch;

    // Card purchase: Swiggy Rs 500 (food).
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_purchase_1',
            ts: ts,
            amount: 500.0,
            direction: 'debit',
            channel: 'card',
            merchantRaw: const Value('Swiggy'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: const Value('settled'),
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    // Credit Card Bill Payment: Rs 5000, unflagged. Merchant text alone does
    // NOT exclude it — FinancialEligibility only excludes by flag.
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_card_bill',
            ts: ts + 1000,
            amount: 5000.0,
            direction: 'debit',
            channel: 'netbanking',
            merchantRaw: const Value('HDFC CREDIT CARD PAYMENT'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: const Value('settled'),
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    // Unflagged: both are counted.
    expect(await categorySum(), 5500.0);

    // Flag the bill as analytics-excluded → it drops out of category totals.
    await (database.update(database.transactions)
          ..where((t) => t.id.equals('txn_card_bill')))
        .write(const TransactionsCompanion(isAnalyticsExcluded: Value(true)));

    expect(await categorySum(), 500.0);
  });

  testWidgets(
      'unflagged credit-card bill shows no false exclusion banner (T-158d)',
      (tester) async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0);

    final txn = Transaction(
      id: 'txn_bill_1',
      ts: ts.millisecondsSinceEpoch,
      amount: 12000.0,
      direction: 'debit',
      channel: 'netbanking',
      merchantRaw: 'SBI CREDIT CARD BILL PAYMENT',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      isDeleted: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: ts,
      updatedAt: ts,
    );

    final detail = TransactionDetail(
      txn: txn,
      merchantName: 'SBI Credit Card',
      categoryName: 'Bills',
      parseConfidence: 0.95,
      confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
      isLowTrustParse: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailProvider('txn_bill_1')
              .overrideWith((ref) => Stream.value(detail)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TransactionDetailScreen(txnId: 'txn_bill_1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // No fabricated "excluded" claim for a row the SQL actually counts.
    expect(find.textContaining('excluded'), findsNothing);
    expect(find.textContaining('Excluded'), findsNothing);
  });

  testWidgets('an analytics-excluded transaction discloses the settings reason',
      (tester) async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0);

    final txn = Transaction(
      id: 'txn_excluded_1',
      ts: ts.millisecondsSinceEpoch,
      amount: 12000.0,
      direction: 'debit',
      channel: 'netbanking',
      merchantRaw: 'SBI CREDIT CARD BILL PAYMENT',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      isDeleted: false,
      isAnalyticsExcluded: true,
      lifecycleState: 'settled',
      createdAt: ts,
      updatedAt: ts,
    );

    final detail = TransactionDetail(
      txn: txn,
      merchantName: 'SBI Credit Card',
      categoryName: 'Bills',
      parseConfidence: 0.95,
      confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
      isLowTrustParse: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailProvider('txn_excluded_1')
              .overrideWith((ref) => Stream.value(detail)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TransactionDetailScreen(txnId: 'txn_excluded_1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.textContaining('Excluded from analytics per settings'),
      findsOneWidget,
    );
  });
}
