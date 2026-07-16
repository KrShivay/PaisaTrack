import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  TransactionListItem item({
    required String id,
    required DateTime ts,
    required double amount,
    required TransactionDirection direction,
    String? displayName,
  }) {
    return TransactionListItem(
      id: id,
      ts: ts,
      amount: amount,
      direction: direction,
      displayName: displayName ?? id,
      categoryName: null,
      categoryId: null,
      categoryIcon: null,
    );
  }

  Future<void> pumpDashboard(
    WidgetTester tester,
    List<TransactionListItem> items, {
    List<RecurringSery> recurring = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionListProvider.overrideWith((ref) => Stream.value(items)),
          reviewQueueProvider.overrideWith((ref) => Stream.value(const [])),
          reviewQueueSummaryProvider.overrideWith(
            (ref) => Stream.value(
              const ReviewQueueSummary(
                count: 0,
                amount: 0,
                merchantCount: 0,
                highestImpactLabel: 'Unknown transaction',
              ),
            ),
          ),
          recurringSeriesProvider
              .overrideWith((ref) => Stream.value(recurring)),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the next recurring items with a full-list action',
      (tester) async {
    final now = DateTime.now();
    await pumpDashboard(
      tester,
      const [],
      recurring: [
        RecurringSery(
          id: 'emi',
          merchantId: 'home_loan',
          label: 'Home loan EMI',
          expectedAmount: 24500,
          tolerancePct: 0.05,
          period: 'monthly',
          periodDays: 30,
          nextExpectedDate: DateTime(now.year, now.month, now.day + 2),
          lastAmount: 24500,
          amountTrend: 'flat',
          occurrences: 4,
          status: 'active',
          kind: 'emi',
        ),
      ],
    );

    await tester.scrollUntilVisible(find.text('Home loan EMI'), 120);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('₹24,500.00'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
  });

  testWidgets('renders hero financial summary for this month', (tester) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 5, 12);
    final lastMonth = DateTime(now.year, now.month - 1, 15, 12);

    await pumpDashboard(tester, [
      item(
        id: 'debit_1',
        ts: thisMonth,
        amount: 150,
        direction: TransactionDirection.debit,
      ),
      item(
        id: 'debit_2',
        ts: thisMonth,
        amount: 50,
        direction: TransactionDirection.debit,
      ),
      item(
        id: 'credit_1',
        ts: thisMonth,
        amount: 100000,
        direction: TransactionDirection.credit,
      ),
      item(
        id: 'debit_last_month',
        ts: lastMonth,
        amount: 9999,
        direction: TransactionDirection.debit,
      ),
    ]);

    expect(find.byType(HeroFinancialCard), findsOneWidget);
    expect(find.text('Net cash flow'), findsOneWidget);
    expect(find.text('+₹99,800.00'), findsOneWidget);
    expect(find.textContaining('Spent', findRichText: true), findsOneWidget);
    expect(find.textContaining('Received', findRichText: true), findsOneWidget);
  });

  testWidgets('shows compact supporting metrics', (tester) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 5, 12);

    await pumpDashboard(tester, [
      item(
        id: 'd',
        ts: thisMonth,
        amount: 200,
        direction: TransactionDirection.debit,
      ),
      item(
        id: 'c',
        ts: thisMonth,
        amount: 1000,
        direction: TransactionDirection.credit,
      ),
    ]);

    expect(find.byType(CompactMetricRow), findsOneWidget);
    expect(find.text('Daily average'), findsOneWidget);
    expect(find.text('vs previous month'), findsOneWidget);
    expect(find.text('Projected'), findsOneWidget);
  });

  testWidgets('shows empty state when no transactions this month',
      (tester) async {
    await pumpDashboard(tester, const []);
    expect(
      find.text(
        'No transactions in ${DashboardPeriod.month(DateTime.now()).label}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('selecting previous month refreshes the dashboard period',
      (tester) async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 5, 12);
    final previous = DateTime(now.year, now.month - 1, 15, 12);
    await pumpDashboard(tester, [
      item(
        id: 'current',
        ts: current,
        amount: 100,
        direction: TransactionDirection.debit,
      ),
      item(
        id: 'previous',
        ts: previous,
        amount: 750,
        direction: TransactionDirection.credit,
      ),
    ]);

    await tester.tap(find.text(DashboardPeriod.month(now).label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous month'));
    await tester.pumpAndSettle();

    expect(
      find.text(DashboardPeriod.month(previous).label),
      findsOneWidget,
    );
    expect(find.text('+₹750.00'), findsWidgets);
    expect(find.text('vs previous month'), findsOneWidget);
    expect(find.text('Projected'), findsNothing);
  });

  testWidgets('opens Ask PaisaTrack from the app bar', (tester) async {
    await pumpDashboard(tester, const []);

    await tester.tap(find.byTooltip('Ask PaisaTrack'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Ask PaisaTrack'), findsOneWidget);
  });

  testWidgets('lays out on a narrow screen with large amounts and long names',
      (tester) async {
    // Force a small phone width; Flutter fails the test on any RenderFlex
    // overflow, so this catches unconstrained rows.
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 5, 12);

    TransactionListItem cat(String id, double amt, String name, String catId) {
      return TransactionListItem(
        id: id,
        ts: thisMonth,
        amount: amt,
        direction: TransactionDirection.debit,
        displayName: 'A Very Long Merchant Name Private Limited $id',
        categoryName: name,
        categoryId: catId,
        categoryIcon: 'shopping_bag',
      );
    }

    await pumpDashboard(tester, [
      cat('a', 1234567.89, 'Groceries and Household Supplies', 'grocery'),
      cat('b', 987654.32, 'Entertainment and Subscriptions', 'entertainment'),
      cat('c', 456789.01, 'Transport and Fuel', 'transport'),
      cat('d', 234567.0, 'Healthcare and Wellness', 'health'),
      cat('e', 123456.0, 'Education and Learning', 'education'),
      cat('f', 99999.0, 'Miscellaneous Other Things', 'misc'),
      item(
        id: 'big_credit',
        ts: thisMonth,
        amount: 5000000,
        direction: TransactionDirection.credit,
      ),
    ]);

    // No overflow assertion is implicit: a RenderFlex overflow throws during
    // pump and fails the test. Confirm the screen actually rendered content.
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(HeroFinancialCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a category opens the filtered transactions list',
      (tester) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 5, 12);

    await pumpDashboard(tester, [
      TransactionListItem(
        id: 'food_1',
        ts: thisMonth,
        amount: 400,
        direction: TransactionDirection.debit,
        displayName: 'Swiggy',
        categoryName: 'Food',
        categoryId: 'food_dining',
        categoryIcon: 'restaurant',
      ),
    ]);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    // The pushed screen is the transactions list, titled with the category and
    // carrying the search field that only that screen has.
    expect(find.widgetWithText(AppBar, 'Food'), findsOneWidget);
    expect(find.text('Search transactions'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Swiggy'), findsOneWidget);
  });
}
