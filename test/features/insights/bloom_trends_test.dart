import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/clock.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTrends(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWith((ref) => () => now),
          dashboardPeriodProvider.overrideWith(
            (ref) => DashboardPeriod.month(
              now,
              calendar: const FinancialCalendar.fixed(Duration.zero),
            ),
          ),
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
        ],
        child: const MaterialApp(
          home: InsightsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom Trends / InsightsScreen', () {
    testWidgets('renders title, Recurring button, and 6-month trend chart',
        (tester) async {
      await pumpTrends(tester, DateTime.utc(2026, 10, 15));

      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
      expect(find.text('INR ANALYTICS'), findsOneWidget);
      expect(
        find.textContaining('Other source currencies are listed separately'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('SPEND TREND (LAST 6 MONTHS)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    });

    testWidgets('lists foreign and unknown source totals separately',
        (tester) async {
      await pumpTrends(tester, DateTime.utc(2026, 10, 15));

      await tester.scrollUntilVisible(
        find.text('OTHER SOURCE CURRENCIES · THIS PERIOD'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining(r'$25.00 USD'), findsOneWidget);
      expect(
        find.textContaining(r'$40.00 (currency unknown)'),
        findsOneWidget,
      );
      expect(find.textContaining('no exchange rate'), findsOneWidget);
    });

    testWidgets('renders Month-over-Month comparison card', (tester) async {
      await pumpTrends(tester, DateTime.utc(2026, 10, 15));

      await tester.scrollUntilVisible(
        find.text('MONTH OVER MONTH'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MONTH OVER MONTH'), findsOneWidget);
      expect(find.textContaining('spent so far'), findsOneWidget);
      expect(find.textContaining('vs same days last month'), findsOneWidget);
    });

    testWidgets('last day of month labels the full prior month',
        (tester) async {
      await pumpTrends(tester, DateTime.utc(2026, 10, 31, 12));

      await tester.scrollUntilVisible(
        find.text('MONTH OVER MONTH'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('vs previous month'), findsOneWidget);
      expect(find.textContaining('vs same days last month'), findsNothing);
    });
  });
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
  currencyTotals: [
    DashboardCurrencyAggregate(
      currencyCode: 'USD',
      currencySymbol: r'$',
      debitTotal: 25,
      creditTotal: 0,
    ),
    DashboardCurrencyAggregate(
      currencyCode: null,
      currencySymbol: r'$',
      debitTotal: 40,
      creditTotal: 0,
    ),
  ],
);
