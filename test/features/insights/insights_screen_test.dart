import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
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
        child: const MaterialApp(home: InsightsScreen()),
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
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);
