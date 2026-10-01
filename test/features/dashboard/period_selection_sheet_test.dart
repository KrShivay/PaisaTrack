import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/period_selection_sheet.dart';

void main() {
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
