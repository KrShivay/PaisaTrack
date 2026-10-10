import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/clock.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

DashboardAggregateSnapshot _snapshot({double debitTotal = 0}) {
  return DashboardAggregateSnapshot(
    debitTotal: debitTotal,
    creditTotal: 0,
    previousSpend: 0,
    categories: const [],
    merchants: const [],
    trendByMonth: const {},
  );
}

RecurringSery _recurringSeries(DateTime nextExpectedDate) {
  return RecurringSery(
    id: 'series',
    merchantId: 'merchant',
    label: 'Monthly bill',
    expectedAmount: 750,
    currencyCode: 'INR',
    currencySymbol: '₹',
    tolerancePct: 0.05,
    period: 'monthly',
    periodDays: 30,
    nextExpectedDate: nextExpectedDate,
    lastAmount: 750,
    amountTrend: 'flat',
    occurrences: 1,
    status: 'active',
    kind: 'bill',
  );
}

void main() {
  test('commitments include every active expense but display only three',
      () async {
    final now = DateTime.utc(2026, 7, 15);
    final base = _recurringSeries(now);
    RecurringSery item({
      required String id,
      required double amount,
      String status = 'active',
      String kind = 'bill',
      String? currencyCode = 'INR',
      String? currencySymbol = '₹',
    }) =>
        base.copyWith(
          id: id,
          label: id,
          expectedAmount: amount,
          status: status,
          kind: kind,
          currencyCode: Value(currencyCode),
          currencySymbol: Value(currencySymbol),
        );

    final series = [
      item(id: 'bill-1', amount: 100),
      item(id: 'bill-2', amount: 200),
      item(id: 'bill-3', amount: 300),
      item(id: 'bill-4', amount: 400),
      item(id: 'income', amount: 900, kind: 'income'),
      item(id: 'paused', amount: 1000, status: 'paused'),
      item(id: 'cancelled', amount: 1000, status: 'cancelled'),
      item(id: 'muted', amount: 1000, status: 'muted'),
      item(id: 'unknown', amount: 1000, status: 'unknown'),
      item(id: 'usd', amount: 250, currencyCode: 'USD', currencySymbol: r'$'),
    ];
    final container = ProviderContainer(
      overrides: [
        recurringSeriesProvider.overrideWith(
          (ref) => Stream.value([
            for (final row in series) RecurringSeriesItem(series: row),
          ]),
        ),
        clockProvider.overrideWith((ref) => () => now),
        dashboardPeriodProvider.overrideWith(
          (ref) => DashboardPeriod.month(now),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(recurringSeriesProvider.future);
    expect(
      container.read(upcomingRecurringProvider).map((row) => row.id),
      ['bill-1', 'bill-2', 'bill-3'],
    );
    expect(container.read(commitmentsTotalProvider), 1000);
  });

  test('commitments use financial month membership at a UTC month boundary',
      () {
    const calendar = FinancialCalendar.fixed(Duration(hours: -4));
    final now = DateTime.utc(2026, 9, 1, 3, 30);
    final series = _recurringSeries(DateTime.utc(2026, 9, 1, 4, 30));
    final container = ProviderContainer(
      overrides: [
        financialCalendarProvider.overrideWith((ref) => calendar),
        clockProvider.overrideWith((ref) => () => now),
        dashboardPeriodProvider.overrideWith(
          (ref) => DashboardPeriod.month(now, calendar: calendar),
        ),
        activeRecurringExpensesProvider.overrideWith((ref) => [series]),
      ],
    );
    addTearDown(container.dispose);

    expect(calendar.monthContaining(now).start, DateTime.utc(2026, 8, 1, 4));
    expect(
      calendar.monthContaining(series.nextExpectedDate).start,
      DateTime.utc(2026, 9, 1, 4),
    );
    expect(container.read(commitmentsTotalProvider), 0);
  });

  testWidgets('budget caption says more recurring bills are expected',
      (tester) async {
    final now = DateTime.now();
    final series = _recurringSeries(now);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyBudgetProvider.overrideWith((ref) async => 50000),
          dashboardAggregateProvider.overrideWith(
            (ref) async => _snapshot(debitTotal: 1200),
          ),
          activeRecurringExpensesProvider.overrideWith((ref) => [series]),
          clockProvider.overrideWith((ref) => () => now),
          dashboardPeriodProvider.overrideWith(
            (ref) => DashboardPeriod.month(now),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: BloomBudgetCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '₹48,050.00 left after bills. '
        '₹750.00 recurring bills still expected (gold).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('budget caption is quiet when no recurring bills remain',
      (tester) async {
    final now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyBudgetProvider.overrideWith((ref) async => 50000),
          dashboardAggregateProvider.overrideWith(
            (ref) async => _snapshot(debitTotal: 1200),
          ),
          activeRecurringExpensesProvider.overrideWith((ref) => const []),
          clockProvider.overrideWith((ref) => () => now),
          dashboardPeriodProvider.overrideWith(
            (ref) => DashboardPeriod.month(now),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: BloomBudgetCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '₹48,800.00 left after bills. '
        'No more recurring bills expected this month.',
      ),
      findsOneWidget,
    );
  });
}
