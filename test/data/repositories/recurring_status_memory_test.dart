import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_status_memory.dart';

void main() {
  RecurringSery series({String? code, String? symbol}) => RecurringSery(
        id: 'series',
        merchantId: 'merchant',
        label: 'Service',
        expectedAmount: 100,
        currencyCode: code,
        currencySymbol: symbol,
        tolerancePct: 0.05,
        period: 'monthly',
        periodDays: 30,
        nextExpectedDate: DateTime.utc(2026, 10, 1),
        lastAmount: 100,
        amountTrend: 'flat',
        occurrences: 3,
        status: 'active',
        kind: 'subscription',
      );

  test('legacy unknown series retain their existing status-memory identity',
      () {
    expect(
      RecurringStatusMemory.identity(series()),
      'merchant|subscription|monthly|30|100',
    );
  });

  test('known and bare-symbol series receive separate identities', () {
    final usd =
        RecurringStatusMemory.identity(series(code: 'USD', symbol: r'$'));
    final dollar = RecurringStatusMemory.identity(series(symbol: r'$'));
    expect(usd, isNot(dollar));
    expect(usd, contains('USD'));
    expect(dollar, contains(r'$'));
  });

  test('known ISO identity does not fragment on a missing source symbol', () {
    expect(
      RecurringStatusMemory.identity(series(code: 'USD', symbol: r'$')),
      RecurringStatusMemory.identity(series(code: 'USD')),
    );
  });
}
