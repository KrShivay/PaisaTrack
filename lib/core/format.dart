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
