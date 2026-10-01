import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Converts user-visible local calendar periods into the UTC instants stored
/// in SQLite. PaisaTrack is India-first, so a fixed device offset is adequate
/// for its supported calendar (India has no daylight-saving transitions).
class FinancialCalendar {
  FinancialCalendar({Duration? timeZoneOffset})
      : timeZoneOffset = timeZoneOffset ?? DateTime.now().timeZoneOffset;

  const FinancialCalendar.fixed(this.timeZoneOffset);

  final Duration timeZoneOffset;

  FinancialPeriod dayContaining(DateTime instant) {
    final local = _localWallClock(instant);
    return _period(local.year, local.month, local.day);
  }

  /// Resolves an SMS date-only value without inventing a transaction clock.
  /// Same-day and future dates retain the receive instant; earlier dates use
  /// midnight at that local day's UTC boundary.
  DateTime resolveDateOnly({
    required DateTime date,
    required DateTime receivedAt,
  }) {
    final start = _period(date.year, date.month, date.day).start;
    return start.isBefore(dayContaining(receivedAt).start) ? start : receivedAt;
  }

  FinancialPeriod monthContaining(DateTime instant) {
    final local = _localWallClock(instant);
    return month(local.year, local.month);
  }

  /// Calendar month from local year/month fields, converted to UTC boundaries.
  FinancialPeriod month(int year, int month) =>
      _period(year, month, 1, endMonthOffset: 1);

  /// Calendar day from local date fields, converted to UTC boundaries.
  FinancialPeriod day(int year, int month, int day) =>
      _period(year, month, day);

  /// Clips [prior] to the same elapsed number of local calendar days as
  /// [current] when [current] contains today; completed periods keep [prior].
  FinancialPeriod comparablePrior({
    required FinancialPeriod current,
    required FinancialPeriod prior,
    required DateTime now,
  }) {
    final today = dayContaining(now);
    if (!current.end.isAfter(today.end)) return prior;

    final elapsedDays = this.elapsedDays(current, now);
    if (elapsedDays <= 0) return prior;

    final priorStart = localDate(prior.start);
    final endDate = DateTime.utc(
      priorStart.year,
      priorStart.month,
      priorStart.day + elapsedDays,
    );
    final comparableEnd = day(endDate.year, endDate.month, endDate.day).start;
    return FinancialPeriod(
      start: prior.start,
      end: comparableEnd.isBefore(prior.end) ? comparableEnd : prior.end,
    );
  }

  /// Returns [period] through the end of [now]'s local calendar day.
  FinancialPeriod throughToday(FinancialPeriod period, DateTime now) {
    final todayEnd = dayContaining(now).end;
    return FinancialPeriod(
      start: period.start,
      end: todayEnd.isBefore(period.end) ? todayEnd : period.end,
    );
  }

  /// Counts elapsed local calendar days from [period.start] through today.
  int elapsedDays(FinancialPeriod period, DateTime now) {
    final bounded = throughToday(period, now);
    if (!period.start.isBefore(bounded.end)) return 0;
    return bounded.end.difference(period.start).inDays;
  }

  DateTime localDate(DateTime instant) => _localWallClock(instant);

  String monthKey(DateTime instant) {
    final local = _localWallClock(instant);
    return '${local.year}-${local.month.toString().padLeft(2, '0')}';
  }

  FinancialPeriod _period(
    int year,
    int month,
    int day, {
    int endMonthOffset = 0,
  }) {
    final startWallClock = DateTime.utc(year, month, day);
    final endWallClock = endMonthOffset == 0
        ? startWallClock.add(const Duration(days: 1))
        : DateTime.utc(year, month + endMonthOffset, 1);
    return FinancialPeriod(
      start: startWallClock.subtract(timeZoneOffset),
      end: endWallClock.subtract(timeZoneOffset),
    );
  }

  DateTime _localWallClock(DateTime instant) =>
      instant.toUtc().add(timeZoneOffset);
}

/// Shared calendar used by capture, history import, and catch-up ingestion.
final financialCalendarProvider = Provider<FinancialCalendar>(
  (ref) => FinancialCalendar(),
);

class FinancialPeriod {
  const FinancialPeriod({required this.start, required this.end});

  /// UTC instants suitable for half-open SQLite timestamp queries.
  final DateTime start;
  final DateTime end;

  bool contains(DateTime instant) =>
      !instant.toUtc().isBefore(start) && instant.toUtc().isBefore(end);
}
