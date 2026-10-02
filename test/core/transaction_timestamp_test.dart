import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/core/transaction_timestamp.dart';

void main() {
  test('date selection replaces only the date and preserves the prior time',
      () {
    final selected = replaceLocalDatePreservingTime(
      DateTime(2026, 7, 25),
      DateTime(2026, 7, 26, 23, 59, 42, 123, 456),
    );

    expect(selected, DateTime(2026, 7, 25, 23, 59, 42, 123, 456));
  });

  test('manual entry converts local wall-clock fields through its calendar',
      () {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final instant = financialInstantFromLocalDateTime(
      DateTime(2026, 7, 26, 23, 59),
      calendar,
    );

    expect(instant, DateTime.utc(2026, 7, 26, 18, 29));
    expect(calendar.localDate(instant), DateTime.utc(2026, 7, 26, 23, 59));
  });
}
