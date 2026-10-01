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

  test('comparable prior uses elapsed days in the local calendar', () {
    final now = DateTime.utc(2026, 10, 3, 8);
    final current = calendar.monthContaining(now);
    final prior = calendar.month(2026, 9);
    final comparable = calendar.comparablePrior(
      current: current,
      prior: prior,
      now: now,
    );

    expect(comparable.start, DateTime.utc(2026, 8, 31, 18, 30));
    expect(comparable.end, DateTime.utc(2026, 9, 3, 18, 30));
    expect(calendar.elapsedDays(current, now), 3);
    expect(
      calendar.throughToday(current, now).end,
      DateTime.utc(2026, 10, 3, 18, 30),
    );
  });

  test('completed current period retains the whole prior period', () {
    final current = calendar.month(2026, 9);
    final prior = calendar.month(2026, 8);
    final comparable = calendar.comparablePrior(
      current: current,
      prior: prior,
      now: DateTime.utc(2026, 10, 3),
    );

    expect(comparable.start, prior.start);
    expect(comparable.end, prior.end);
  });

  test('month end clamps a 31-day window to February', () {
    final current = calendar.month(2026, 3);
    final prior = calendar.month(2026, 2);
    final comparable = calendar.comparablePrior(
      current: current,
      prior: prior,
      now: DateTime.utc(2026, 3, 31, 8),
    );

    expect(comparable.start, prior.start);
    expect(comparable.end, prior.end);
  });

  test('January partial window compares against December across year boundary',
      () {
    final current = calendar.month(2027, 1);
    final prior = calendar.month(2026, 12);
    final comparable = calendar.comparablePrior(
      current: current,
      prior: prior,
      now: DateTime.utc(2027, 1, 3, 8),
    );

    expect(comparable.start, DateTime.utc(2026, 11, 30, 18, 30));
    expect(comparable.end, DateTime.utc(2026, 12, 3, 18, 30));
  });

  test('comparable windows use fixed negative offsets as local dates', () {
    const negativeOffset = FinancialCalendar.fixed(Duration(hours: -5));
    final now = DateTime.utc(2026, 10, 4, 1);
    final comparable = negativeOffset.comparablePrior(
      current: negativeOffset.month(2026, 10),
      prior: negativeOffset.month(2026, 9),
      now: now,
    );

    expect(comparable.start, DateTime.utc(2026, 9, 1, 5));
    expect(comparable.end, DateTime.utc(2026, 9, 4, 5));
  });
}
