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
}
