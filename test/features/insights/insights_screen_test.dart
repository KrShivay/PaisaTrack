import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  test('insight period key uses the period calendar across UTC month edge', () {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final period = DashboardPeriod.month(
      DateTime.utc(2026, 10, 15, 12),
      calendar: calendar,
    );

    expect(period.start, DateTime.utc(2026, 9, 30, 18, 30));
    expect(insightMonthKeyForPeriod(period), '2026-10');
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders Bloom Trends header and 6-month spend chart',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('MONTH OVER MONTH'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MONTH OVER MONTH'), findsOneWidget);
  });

  testWidgets('offers retry when analytics fail and recovers on retry',
      (tester) async {
    var attempts = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw StateError('offline');
            return _emptyDashboardAggregate;
          }),
          activeInsightsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't load spending analytics."), findsOneWidget);
    expect(find.textContaining('Pull to refresh'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(attempts, 2);
    expect(find.text("Couldn't load spending analytics."), findsNothing);
    expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(600, 900)]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
        'Trends has no overflow at ${size.width.toInt()}px and $scale× text',
        (tester) async {
          await pumpScreen(tester, size: size, textScale: scale);

          expect(find.text('Trends'), findsOneWidget);
          if (scale >= 1.5) {
            final recurring = find.byTooltip('Recurring transactions');
            expect(recurring, findsOneWidget);
            expect(tester.getSize(recurring), const Size(48, 48));
          } else {
            expect(find.text('Recurring'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);
