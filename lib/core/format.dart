/// Formats rupee amounts with Indian digit grouping and two decimals.
String formatInr(double amount) {
  final sign = amount.isNegative ? '-' : '';
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first;
  final decimals = parts.last;

  if (whole.length <= 3) {
    return '$sign₹$whole.$decimals';
  }

  final lastThree = whole.substring(whole.length - 3);
  final leading = whole.substring(0, whole.length - 3);
  final groups = <String>[];

  for (var end = leading.length; end > 0; end -= 2) {
    final start = end - 2 < 0 ? 0 : end - 2;
    groups.insert(0, leading.substring(start, end));
  }

  return '$sign₹${groups.join(',')},$lastThree.$decimals';
}

/// Formats a parsed source amount without implying an exchange rate or
/// assigning an ISO currency to an ambiguous symbol.
String formatSourceAmount(
  double amount, {
  String? currencyCode,
  String? currencySymbol,
}) {
  if (currencyCode == 'INR') return formatInr(amount);
  final sign = amount.isNegative ? '-' : '';
  final value = amount.abs().toStringAsFixed(2);
  if (currencyCode != null) {
    return '$sign${currencySymbol ?? currencyCode}$value $currencyCode';
  }
  if (currencySymbol != null) {
    return '$sign$currencySymbol$value (currency unknown)';
  }
  return '$sign$value (currency unknown)';
}

/// Compact rupee format for charts and stats (e.g. ₹4.5k, ₹1.2L).
String formatInrCompact(double amount) {
  final absVal = amount.abs();
  final sign = amount.isNegative ? '-' : '';
  if (absVal >= 100000) {
    return '$sign₹${(absVal / 100000).toStringAsFixed(1)}L';
  } else if (absVal >= 1000) {
    return '$sign₹${(absVal / 1000).toStringAsFixed(1)}k';
  }
  return '$sign₹${absVal.toStringAsFixed(0)}';
}

const _monthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Returns the compact English month label used by transaction dates.
String formatMonthAbbreviation(int month) => _monthAbbrev[month - 1];

/// Formats a calendar month for user-facing period labels, such as October 2026.
String formatMonthYear(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.year}';

/// Converts legacy ISO period labels to the same concise labels used by range
/// validation while preserving already-human relative labels.
String formatPeriodLabel(String label) {
  final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(label);
  if (month != null) {
    final year = int.parse(month.group(1)!);
    final monthNumber = int.parse(month.group(2)!);
    if (monthNumber >= 1 && monthNumber <= 12) {
      return formatMonthYear(DateTime(year, monthNumber));
    }
  }
  final range = RegExp(
    r'^(\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})$',
  ).firstMatch(label);
  if (range != null) {
    return formatIsoDateRange(range.group(1)!, range.group(2)!);
  }
  return label;
}

String _clock12h(DateTime t) {
  final hour24 = t.hour;
  final period = hour24 < 12 ? 'AM' : 'PM';
  var hour = hour24 % 12;
  if (hour == 0) hour = 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}

/// Formats a local date's clock in the lowercase 12-hour style used by detail.
String formatClockTime12h(DateTime date) =>
    _clock12h(date.toLocal()).toLowerCase();

/// Formats a transaction instant as a local 12-hour clock, such as "12:00 am".
/// [localize] is injectable so timezone-boundary behavior can be tested without
/// depending on the machine running the test. Production callers use local time.
String formatTxnClockTime(
  DateTime ts, {
  DateTime Function(DateTime instant)? localize,
}) {
  final local = (localize ?? _toLocal)(ts);
  final clock = _clock12h(local);
  return clock.toLowerCase();
}

DateTime _toLocal(DateTime instant) => instant.toLocal();

/// Compact time-of-day / date shown in a transaction tile subtitle.
///
/// Today -> "3:45 PM"; earlier this year -> "7 Jul"; otherwise "7 Jul 24".
/// [now] is injectable for deterministic tests.
String formatTxnTime(DateTime ts, {DateTime? now}) {
  final local = ts.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final isSameDay = local.year == ref.year &&
      local.month == ref.month &&
      local.day == ref.day;
  if (isSameDay) return _clock12h(local);

  final day = local.day;
  final mon = _monthAbbrev[local.month - 1];
  if (local.year == ref.year) return '$day $mon';
  return '$day $mon ${(local.year % 100).toString().padLeft(2, '0')}';
}

/// Human date-group header for a list section: "Today", "Yesterday",
/// "7 July", or "7 July 2024". [now] is injectable for deterministic tests.
String formatDateGroup(DateTime ts, {DateTime? now}) {
  final local = ts.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final diff = _localCalendarDayDifference(local, ref);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';

  final base = '${local.day} ${_monthNames[local.month - 1]}';
  return local.year == ref.year ? base : '$base ${local.year}';
}

/// Formats a local calendar day in the compact style used by Activity.
///
/// Calendar comparisons use UTC date components, not elapsed local-midnight
/// durations, so yesterday remains yesterday across daylight-saving changes.
String formatActivityDateGroup(DateTime ts, {DateTime? now}) {
  final local = ts.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final diff = _localCalendarDayDifference(local, ref);
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';

  final base = '${_monthAbbrev[local.month - 1].toUpperCase()} ${local.day}';
  return local.year == ref.year ? base : '$base ${local.year}';
}

int _localCalendarDayDifference(DateTime localFrom, DateTime localTo) {
  final fromDate = DateTime.utc(localFrom.year, localFrom.month, localFrom.day);
  final toDate = DateTime.utc(localTo.year, localTo.month, localTo.day);
  return toDate.difference(fromDate).inDays;
}

/// Formats ISO calendar-date ranges for short insight copy.
/// Same-day ranges collapse to one date; years appear only when they differ.
String formatIsoDateRange(String startIso, String endIso) {
  DateTime? parseDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      return null;
    }
    return parsed;
  }

  final start = parseDate(startIso);
  final end = parseDate(endIso);
  if (start == null || end == null) return '$startIso–$endIso';

  String shortDate(DateTime date, {bool includeYear = false}) {
    final label = '${formatMonthAbbreviation(date.month)} ${date.day}';
    return includeYear ? '$label, ${date.year}' : label;
  }

  if (start == end) return shortDate(start);
  if (start.year == end.year && start.month == end.month) {
    return '${formatMonthAbbreviation(start.month)} ${start.day}–${end.day}';
  }
  final includeYear = start.year != end.year;
  return '${shortDate(start, includeYear: includeYear)}–'
      '${shortDate(end, includeYear: includeYear)}';
}
