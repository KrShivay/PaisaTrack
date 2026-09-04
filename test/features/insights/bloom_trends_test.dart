import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTrends(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
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
      await pumpTrends(tester);

      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
      expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    });

    testWidgets('renders Month-over-Month comparison card', (tester) async {
      await pumpTrends(tester);

      await tester.scrollUntilVisible(
        find.text('MONTH OVER MONTH'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MONTH OVER MONTH'), findsOneWidget);
      expect(find.textContaining('spent so far'), findsOneWidget);
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
);
