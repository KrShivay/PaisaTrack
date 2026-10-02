import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_theme.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/period_selection_sheet.dart';

void main() {
  testWidgets('custom range Save accepts the 48dp target edge at 1.5x and 2x text',
      (tester) async {
    for (final scale in [1.5, 2.0]) {
      tester.view.physicalSize = const Size(434, 964);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const ProviderScope(
            child: Scaffold(body: BloomDatePeriodSheet()),
          ),
        ),
      );
      await tester.tap(find.textContaining('Custom date range'));
      await tester.pumpAndSettle();

      final label = tester.getRect(find.text('Save'));
      await tester.tapAt(Offset(label.center.dx, label.center.dy + 23));
      await tester.pumpAndSettle();
      expect(find.text('Select Period'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  test('October IST month seed uses local dates and clamps to today', () {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final period = DashboardPeriod.month(
      DateTime.utc(2026, 10, 15, 12),
      calendar: calendar,
    );

    final seed = dateRangePickerSeed(
      period: period,
      lastDate: DateTime(2026, 10, 15, 18),
    );

    expect((seed.start.year, seed.start.month, seed.start.day), (2026, 10, 1));
    expect((seed.end.year, seed.end.month, seed.end.day), (2026, 10, 15));
    expect(seed.start.isAfter(seed.end), isFalse);
  });

  test('custom range uses its inclusive local calendar days', () {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final period = DashboardPeriod.range(
      DateTime.utc(2026, 9, 29, 18, 30),
      DateTime.utc(2026, 10, 2, 18, 29),
      calendar: calendar,
    );

    final seed = dateRangePickerSeed(
      period: period,
      lastDate: DateTime(2026, 10, 2),
    );

    expect((seed.start.year, seed.start.month, seed.start.day), (2026, 9, 30));
    expect((seed.end.year, seed.end.month, seed.end.day), (2026, 10, 2));
  });
}
