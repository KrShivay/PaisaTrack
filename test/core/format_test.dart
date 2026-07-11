import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/format.dart';

void main() {
  group('formatInr', () {
    test('formats amounts below one lakh with standard thousands grouping', () {
      expect(formatInr(0), '₹0.00');
      expect(formatInr(12), '₹12.00');
      expect(formatInr(1234.5), '₹1,234.50');
      expect(formatInr(99999.999), '₹1,00,000.00');
    });

    test('formats lakhs and crores with Indian digit grouping', () {
      expect(formatInr(100000), '₹1,00,000.00');
      expect(formatInr(1234567.89), '₹12,34,567.89');
      expect(formatInr(123456789.01), '₹12,34,56,789.01');
    });

    test('keeps a leading minus sign for negative amounts', () {
      expect(formatInr(-1234567.89), '-₹12,34,567.89');
    });
  });

  group('formatTxnTime', () {
    final now = DateTime(2026, 7, 11, 15, 30);

    test('shows 12-hour clock for same-day timestamps', () {
      expect(formatTxnTime(DateTime(2026, 7, 11, 9, 5), now: now), '9:05 AM');
      expect(formatTxnTime(DateTime(2026, 7, 11, 0, 0), now: now), '12:00 AM');
      expect(formatTxnTime(DateTime(2026, 7, 11, 13, 45), now: now), '1:45 PM');
    });

    test('shows day and month earlier in the same year', () {
      expect(formatTxnTime(DateTime(2026, 7, 6, 9), now: now), '6 Jul');
    });

    test('includes two-digit year for prior years', () {
      expect(formatTxnTime(DateTime(2024, 12, 31, 9), now: now), '31 Dec 24');
    });
  });

  group('formatDateGroup', () {
    final now = DateTime(2026, 7, 11, 15, 30);

    test('labels today and yesterday', () {
      expect(formatDateGroup(DateTime(2026, 7, 11, 8), now: now), 'Today');
      expect(formatDateGroup(DateTime(2026, 7, 10, 8), now: now), 'Yesterday');
    });

    test('labels older dates with full month, adding year across years', () {
      expect(formatDateGroup(DateTime(2026, 7, 4, 8), now: now), '4 July');
      expect(
        formatDateGroup(DateTime(2025, 12, 30, 8), now: now),
        '30 December 2025',
      );
    });
  });
}
