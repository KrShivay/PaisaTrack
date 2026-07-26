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

String _clock12h(DateTime t) {
  final hour24 = t.hour;
  final period = hour24 < 12 ? 'AM' : 'PM';
  var hour = hour24 % 12;
  if (hour == 0) hour = 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute $period';
}

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
  final thatDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final diff = today.difference(thatDay).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';

  const months = [
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
  final base = '${local.day} ${months[local.month - 1]}';
  return local.year == ref.year ? base : '$base ${local.year}';
}
