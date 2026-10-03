import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/format.dart';
import 'package:paisatrack/features/transactions/detail/transaction_detail_formatting.dart';

void main() {
  test('formatMonthYear uses a full human-readable month label', () {
    expect(formatMonthYear(DateTime(2026, 10)), 'October 2026');
  });

  test('formatPeriodLabel humanizes ISO month and date-range labels', () {
    expect(formatPeriodLabel('2026-10'), 'October 2026');
    expect(formatPeriodLabel('2026-10-02 to 2026-10-03'), 'Oct 2–3');
    expect(formatPeriodLabel('this month to date'), 'this month to date');
  });

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

  group('formatIsoDateRange', () {
    test('collapses one day and shortens same-month ranges', () {
      expect(formatIsoDateRange('2026-10-01', '2026-10-01'), 'Oct 1');
      expect(formatIsoDateRange('2026-10-01', '2026-10-02'), 'Oct 1–2');
    });

    test('keeps both month names and adds years across years', () {
      expect(formatIsoDateRange('2026-09-01', '2026-10-02'), 'Sep 1–Oct 2');
      expect(
        formatIsoDateRange('2025-12-30', '2026-01-02'),
        'Dec 30, 2025–Jan 2, 2026',
      );
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

  group('formatTxnClockTime', () {
    test('localizes an IST midnight instant without changing its epoch', () {
      final instant = DateTime.utc(2026, 7, 10, 18, 30);
      final storedEpoch = instant.millisecondsSinceEpoch;

      final result = formatTxnClockTime(
        instant,
        localize: (value) => value.add(const Duration(hours: 5, minutes: 30)),
      );

      expect(result, '12:00 am');
      expect(instant.millisecondsSinceEpoch, storedEpoch);
    });

    test('uses the currently injected offset after a timezone change', () {
      final instant = DateTime.utc(2026, 7, 10, 18, 30);

      expect(
        formatTxnClockTime(
          instant,
          localize: (value) => value.add(const Duration(hours: -4)),
        ),
        '2:30 pm',
      );
    });

    test('agrees with detail and grouping for a local midnight', () {
      final localMidnight = DateTime(2026, 7, 11);
      final now = DateTime(2026, 7, 11, 12);

      expect(
        formatTxnClockTime(localMidnight, localize: (value) => value),
        '12:00 am',
      );
      expect(formatDetailDate(localMidnight), 'Jul 11, 2026 · 12:00 am');
      expect(formatDateGroup(localMidnight, now: now), 'Today');
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

    test('uses calendar dates for yesterday across DST and year boundaries',
        () {
      final springNow = DateTime(2026, 3, 9, 0, 30);
      final springYesterday = DateTime(2026, 3, 8, 0, 30);
      if (springNow.timeZoneOffset != springYesterday.timeZoneOffset) {
        expect(
          springNow.difference(springYesterday),
          const Duration(hours: 23),
        );
      }
      expect(formatDateGroup(springYesterday, now: springNow), 'Yesterday');
      expect(
        formatActivityDateGroup(springYesterday, now: springNow),
        'YESTERDAY',
      );

      final fallNow = DateTime(2026, 11, 2, 0, 30);
      final fallYesterday = DateTime(2026, 11, 1, 0, 30);
      if (fallNow.timeZoneOffset != fallYesterday.timeZoneOffset) {
        expect(
          fallNow.difference(fallYesterday),
          const Duration(hours: 25),
        );
      }
      expect(formatDateGroup(fallYesterday, now: fallNow), 'Yesterday');
      expect(
        formatActivityDateGroup(fallYesterday, now: fallNow),
        'YESTERDAY',
      );

      final newYear = DateTime(2026, 1, 1, 0, 30);
      final yearBoundaryYesterday = DateTime(2025, 12, 31, 0, 30);
      expect(
        formatDateGroup(yearBoundaryYesterday, now: newYear),
        'Yesterday',
      );
      expect(
        formatActivityDateGroup(yearBoundaryYesterday, now: newYear),
        'YESTERDAY',
      );
    });

    test('preserves Activity headers and adds a year for prior-year dates', () {
      final reference = DateTime(2026, 7, 11, 15, 30);

      expect(
        formatActivityDateGroup(DateTime(2026, 7, 4, 8), now: reference),
        'JUL 4',
      );
      expect(
        formatActivityDateGroup(DateTime(2025, 7, 4, 8), now: reference),
        'JUL 4 2025',
      );
    });
  });

  test('formatPercentChange scales a fraction and drops the sign', () {
    expect(formatPercentChange(0.5912), '59%');
    expect(formatPercentChange(-0.5912, decimals: 1), '59.1%');
    expect(formatPercentChange(0.004, decimals: 1), '0.4%');
  });
}
