import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/field_normalizer.dart';

void main() {
  const normalizer = FieldNormalizer();

  test('parses Indian comma amount formats', () {
    expect(normalizer.parseAmount('₹1,00,000.50'), 100000.50);
    expect(normalizer.parseAmount('Rs. 449'), 449);
    expect(normalizer.parseAmount('INR 2,500.25'), 2500.25);
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
}
