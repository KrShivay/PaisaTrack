import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/field_normalizer.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/core/financial_calendar.dart';

void main() {
  const normalizer = FieldNormalizer(
    calendar: FinancialCalendar.fixed(Duration.zero),
  );

  test('parses Indian comma amount formats', () {
    expect(normalizer.parseAmount('₹1,00,000.50'), 100000.50);
    expect(normalizer.parseAmount('Rs. 449'), 449);
    expect(normalizer.parseAmount('INR 2,500.25'), 2500.25);
  });

  test('uses amount-adjacent currency token, not a later limit token', () {
    final template = SmsTemplate(
      id: 'axis_usd_fixture',
      regex: RegExp(
        r'Spent (?:USD|INR) (?<amount>[\d,]+)\nAxis Card (?<account>\d{4})\n(?<date>\d{2}-\d{2}-\d{2})\n(?<merchant>.+?)\nAvl Limit: INR [\d,]+',
        caseSensitive: false,
      ),
      direction: 'debit',
      channel: 'card',
      dateFormat: 'dd-MM-yy',
    );
    const istNormalizer = FieldNormalizer(
      calendar: FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );
    const body =
        'Spent USD 2525\nAxis Card 2525\n02-09-26\nSHOP\nAvl Limit: INR 500';
    final receivedAt = DateTime.utc(2026, 9, 1, 22, 10);
    final record = istNormalizer.normalizeTemplateMatch(
      match: template.regex.firstMatch(body)!,
      template: template,
      fallbackTimestamp: receivedAt,
    );

    expect(record.amount, 2525);
    expect(record.currencyCode, 'USD');
    expect(record.currencySymbol, r'$');
    expect(record.ts, receivedAt);
  });

  test('parses dd-MM-yy dates', () {
    expect(
      normalizer.parseDate(
        value: '05-07-26',
        format: 'dd-MM-yy',
        receivedAt: DateTime.utc(2026, 12, 31),
      ),
      DateTime.utc(2026, 7, 5),
    );
  });

  test('same local day keeps the receive instant in IST', () {
    const istNormalizer = FieldNormalizer(
      calendar: FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );
    final receivedAt = DateTime.utc(2026, 7, 5, 22, 10, 37);
    final parsed = istNormalizer.parseDate(
      value: '06-07-26',
      format: 'dd-MM-yy',
      receivedAt: receivedAt,
    );

    expect(parsed, receivedAt);
  });

  test('earlier local day resolves to local midnight at negative offset', () {
    const negativeOffsetNormalizer = FieldNormalizer(
      calendar: FinancialCalendar.fixed(Duration(hours: -5)),
    );
    final receivedAt = DateTime.utc(2026, 3, 2, 17);
    final parsed = negativeOffsetNormalizer.parseDate(
      value: '01-03-26',
      format: 'dd-MM-yy',
      receivedAt: receivedAt,
    );

    expect(parsed, DateTime.utc(2026, 3, 1, 5));
    final localDate = negativeOffsetNormalizer.calendar.localDate(parsed);
    expect((localDate.year, localDate.month, localDate.day), (2026, 3, 1));
  });

  test('future local date retains the receive instant in IST', () {
    const istNormalizer = FieldNormalizer(
      calendar: FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );
    final receivedAt = DateTime.utc(2026, 3, 1, 22, 10);
    final parsed = istNormalizer.parseDate(
      value: '03-03-26',
      format: 'dd-MM-yy',
      receivedAt: receivedAt,
    );

    expect(parsed, receivedAt);
  });

  test('earlier parsed date uses configured local midnight instant', () {
    final parsed = normalizer.parseDate(
      value: '05/07/26',
      format: 'dd/MM/yy',
      receivedAt: DateTime.utc(2026, 12, 31),
    );

    expect(parsed.isUtc, isTrue);
    expect(
      parsed.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 5).millisecondsSinceEpoch,
    );
  });

  test('parses dd-MM-yyyy four-digit-year dates', () {
    expect(
      normalizer.parseDate(
        value: '02-01-2023',
        format: 'dd-MM-yyyy',
        receivedAt: DateTime.utc(2026, 12, 31),
      ),
      DateTime.utc(2023, 1, 2),
    );
  });

  test('parses ddMMMyy separator-less alpha-month dates', () {
    expect(
      normalizer.parseDate(
        value: '08Oct23',
        format: 'ddMMMyy',
        receivedAt: DateTime.utc(2026, 12, 31),
      ),
      DateTime.utc(2023, 10, 8),
    );
  });

  test('falls back on malformed ddMMMyy value', () {
    expect(
      normalizer.parseDate(
        value: '08Xyz23',
        format: 'ddMMMyy',
        receivedAt: DateTime.utc(2026, 5, 1),
      ),
      DateTime.utc(2026, 5, 1),
    );
  });

  test('rejects normalized calendar dates and preserves receive instant', () {
    for (final (value, format) in [
      ('31-02-26', 'dd-MM-yy'),
      ('29-02-23', 'dd-MM-yy'),
      ('31/04/2026', 'dd/MM/yyyy'),
      ('31-Feb-26', 'dd-MMM-yy'),
      ('31Feb26', 'ddMMMyy'),
    ]) {
      expect(
        normalizer.parseDateComponents(value: value, format: format),
        isNull,
        reason: '$value ($format)',
      );
    }

    final receivedAt = DateTime.utc(2026, 5, 1, 18, 42, 13);
    expect(
      normalizer.parseDate(
        value: '31-02-26',
        format: 'dd-MM-yy',
        receivedAt: receivedAt,
      ),
      receivedAt,
    );
  });

  test('accepts valid leap day across numeric and alphabetic month formats',
      () {
    for (final (value, format) in [
      ('29-02-24', 'dd-MM-yy'),
      ('29-02-2024', 'dd-MM-yyyy'),
      ('29-Feb-24', 'dd-MMM-yy'),
      ('29Feb24', 'ddMMMyy'),
    ]) {
      expect(
        normalizer.parseDateComponents(value: value, format: format),
        DateTime.utc(2024, 2, 29),
        reason: '$value ($format)',
      );
    }
  });
}
