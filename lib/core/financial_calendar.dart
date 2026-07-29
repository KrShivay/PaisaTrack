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

  FinancialPeriod monthContaining(DateTime instant) {
    final local = _localWallClock(instant);
    return _period(local.year, local.month, 1, endMonthOffset: 1);
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

class FinancialPeriod {
  const FinancialPeriod({required this.start, required this.end});

  /// UTC instants suitable for half-open SQLite timestamp queries.
  final DateTime start;
  final DateTime end;

  bool contains(DateTime instant) =>
      !instant.toUtc().isBefore(start) && instant.toUtc().isBefore(end);
}
