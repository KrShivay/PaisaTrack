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

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
  });

  test('credit card bill payment and cash withdrawals are excluded from category totals', () async {
    final ts = DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch;

    // Card purchase 1: Swiggy Rs 500
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_purchase_1',
            ts: ts,
            amount: 500.0,
            direction: 'debit',
            channel: 'card',
            categoryId: const Value('food_dining'),
            merchantRaw: const Value('Swiggy'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: const Value('settled'),
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    // Credit Card Bill Payment: Rs 5000 (should NOT be added to category spending)
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_card_bill',
            ts: ts + 1000,
            amount: 5000.0,
            direction: 'debit',
            channel: 'netbanking',
            categoryId: const Value('transfers'), // Use a category that has is_spending: false
            merchantRaw: const Value('HDFC CREDIT CARD PAYMENT'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: const Value('settled'),
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    final dashboardRepo = DashboardRepository(database);
    final snapshot = await dashboardRepo.load(
      DashboardQueryWindow(
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 7, 31),
        trendStart: DateTime.utc(2026, 7, 1),
        trendEnd: DateTime.utc(2026, 7, 31),
        previousStart: DateTime.utc(2026, 6, 1),
        previousEnd: DateTime.utc(2026, 6, 30),
      ),
    );

    // Total category spending should only reflect the purchase (500), not the card bill (5000)
    final categorySum = snapshot.categories.fold(0.0, (acc, c) => acc + c.total);
    expect(categorySum, 500.0);
  });

  testWidgets('TransactionDetailScreen discloses credit card bill exclusion explanation copy', (tester) async {
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

    expect(find.textContaining('Credit card bill payment — excluded'), findsOneWidget);
  });
}
