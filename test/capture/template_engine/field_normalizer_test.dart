import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/field_normalizer.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

void main() {
  const normalizer = FieldNormalizer();

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
    const body =
        'Spent USD 2525\nAxis Card 2525\n01-09-26\nSHOP\nAvl Limit: INR 500';
    final record = normalizer.normalizeTemplateMatch(
      match: template.regex.firstMatch(body)!,
      template: template,
      fallbackTimestamp: DateTime.utc(2026, 9, 1),
    );

    expect(record.amount, 2525);
    expect(record.currencyCode, 'USD');
    expect(record.currencySymbol, r'$');
  });

  test('parses dd-MM-yy dates', () {
    expect(
      normalizer.parseDate(
        value: '05-07-26',
        format: 'dd-MM-yy',
        fallback: DateTime.utc(2026),
      ),
      DateTime.utc(2026, 7, 5),
    );
  });

  test('parsed date epoch milliseconds are timezone-stable', () {
    final parsed = normalizer.parseDate(
      value: '05/07/26',
      format: 'dd/MM/yy',
      fallback: DateTime.utc(2026),
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
        fallback: DateTime.utc(2026),
      ),
      DateTime.utc(2023, 1, 2),
    );
  });

  test('parses ddMMMyy separator-less alpha-month dates', () {
    expect(
      normalizer.parseDate(
        value: '08Oct23',
        format: 'ddMMMyy',
        fallback: DateTime.utc(2026),
      ),
      DateTime.utc(2023, 10, 8),
    );
  });

  test('falls back on malformed ddMMMyy value', () {
    expect(
      normalizer.parseDate(
        value: '08Xyz23',
        format: 'ddMMMyy',
        fallback: DateTime.utc(2026, 5, 1),
      ),
      DateTime.utc(2026, 5, 1),
    );
  });
}
