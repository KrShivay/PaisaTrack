import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/source_currency.dart';

void main() {
  test('currency buckets distinguish ambiguous dollars from explicit USD', () {
    const usd = SourceCurrency(code: 'USD', symbol: r'$');
    const bareDollar = SourceCurrency(symbol: r'$');
    const rupees = SourceCurrency(code: 'INR', symbol: '₹');

    expect(usd.bucketKey, 'code:USD');
    expect(bareDollar.bucketKey, r'symbol:$');
    expect(usd.sameBucket(const SourceCurrency(code: 'USD')), isTrue);
    expect(usd.sameBucket(bareDollar), isFalse);
    expect(rupees.sameBucket(usd), isFalse);
  });

  test('legacy row JSON without currency restores as unknown', () {
    final now = DateTime.utc(2026, 9, 1);
    final transactionJson = Transaction(
      id: 'legacy',
      ts: 1,
      amount: 25,
      direction: 'debit',
      channel: 'card',
      parseSource: 'template',
      confidenceJson: '{}',
      status: 'confirmed',
      isDeleted: false,
      isNotTransaction: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: now,
      updatedAt: now,
    ).toJson()
      ..remove('currencyCode')
      ..remove('currencySymbol');
    final recurringJson = RecurringSery(
      id: 'legacy-series',
      merchantId: 'merchant',
      label: 'Service',
      expectedAmount: 25,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: now,
      lastAmount: 25,
      amountTrend: 'flat',
      occurrences: 2,
      status: 'active',
      kind: 'subscription',
    ).toJson()
      ..remove('currencyCode')
      ..remove('currencySymbol');

    expect(Transaction.fromJson(transactionJson).currencyCode, isNull);
    expect(Transaction.fromJson(transactionJson).currencySymbol, isNull);
    expect(RecurringSery.fromJson(recurringJson).currencyCode, isNull);
    expect(RecurringSery.fromJson(recurringJson).currencySymbol, isNull);
  });
}
