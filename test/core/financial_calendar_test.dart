import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';

void main() {
  const ist = Duration(hours: 5, minutes: 30);
  const calendar = FinancialCalendar.fixed(ist);

  test('maps the local month boundary to half-open UTC query instants', () {
    final july = calendar.monthContaining(DateTime.utc(2026, 7, 31, 18, 29));
    final august = calendar.monthContaining(DateTime.utc(2026, 7, 31, 18, 30));

    expect(july.start, DateTime.utc(2026, 6, 30, 18, 30));
    expect(july.end, DateTime.utc(2026, 7, 31, 18, 30));
    expect(july.contains(DateTime.utc(2026, 7, 31, 18, 29)), isTrue);
    expect(july.contains(DateTime.utc(2026, 7, 31, 18, 30)), isFalse);
    expect(august.start, july.end);
    expect(calendar.monthKey(DateTime.utc(2026, 7, 31, 18, 30)), '2026-08');
  });

  test('DashboardPeriod uses the same injected local month boundary', () {
    final period = DashboardPeriod.month(
      DateTime.utc(2026, 7, 31, 18, 30),
      calendar: calendar,
    );

    expect(period.label, 'August 2026');
    expect(period.start, DateTime.utc(2026, 7, 31, 18, 30));
    expect(period.end, DateTime.utc(2026, 8, 31, 18, 30));
    expect(period.contains(DateTime.utc(2026, 7, 31, 18, 29)), isFalse);
    expect(period.contains(DateTime.utc(2026, 7, 31, 18, 30)), isTrue);
  });
}
