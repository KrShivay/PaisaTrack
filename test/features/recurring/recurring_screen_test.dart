import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  RecurringSery series({
    String id = 'series_1',
    String label = 'Netflix',
    String kind = 'subscription',
    String trend = 'flat',
    String status = 'active',
  }) {
    return RecurringSery(
      id: id,
      merchantId: 'merchant_$id',
      label: label,
      expectedAmount: 499,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: DateTime.utc(2026, 8, 1),
      lastAmount: 499,
      amountTrend: trend,
      occurrences: 4,
      status: status,
      kind: kind,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<RecurringSery> rows, {
    List<TransactionListItem> transactions = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recurringSeriesProvider.overrideWith((ref) => Stream.value(rows)),
          transactionListProvider.overrideWith(
            (ref) => Stream.value(transactions),
          ),
        ],
        child: const MaterialApp(home: RecurringScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows designed empty state', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No recurring activity yet'), findsOneWidget);
    expect(
      find.textContaining('after three matching transactions'),
      findsOneWidget,
    );
  });

  testWidgets('renders upcoming, rising, and missed series', (tester) async {
    await pumpScreen(tester, [
      series(trend: 'rising'),
      series(
        id: 'series_2',
        label: 'Electricity bill',
        kind: 'bill',
        status: 'missed',
      ),
    ]);

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.byKey(const ValueKey('price_creep_badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('missed_badge')), findsOneWidget);
    expect(find.textContaining('Next expected'), findsOneWidget);
    expect(find.textContaining('Expected'), findsWidgets);
  });

  testWidgets('tap opens the merchant transaction list', (tester) async {
    final txn = TransactionListItem(
      id: 'txn_1',
      ts: DateTime.utc(2026, 7, 1),
      amount: 499,
      direction: TransactionDirection.debit,
      displayName: 'Netflix',
      categoryName: 'Subscriptions',
      categoryId: 'subscriptions',
      categoryIcon: 'subscriptions',
    );
    await pumpScreen(tester, [series()], transactions: [txn]);

    await tester.tap(find.text('Netflix'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Netflix'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Netflix'), findsOneWidget);
  });
}
