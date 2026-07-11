import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';

void main() {
  test('suggests curated icons for requested category phrases', () {
    const cases = {
      'Cigarette': 'smoking_rooms',
      'Tobacco': 'smoking_rooms',
      'Smoke': 'smoking_rooms',
      'Transfer to Wife': 'swap_horiz',
      'Send family allowance to husband': 'swap_horiz',
      'Doctor visit': 'medical_services',
      'Medicine from pharmacy': 'medical_services',
      'Rent to landlord': 'home',
      'Housing': 'home',
      'Salon haircut and grooming': 'content_cut',
      'Tea + Cigarette': 'smoking_rooms',
      'Mutual fund investment': 'show_chart',
      'Redemption': 'currency_exchange',
      'Bike service': 'two_wheeler',
      'WiFi payment': 'wifi',
      'Mobile recharge': 'phone_android',
      'Claude subscription payment': 'smart_toy',
      'Codex subscription payment': 'smart_toy',
      'Salary': 'payments',
      'Dividend': 'account_balance_wallet',
      'Stocks': 'candlestick_chart',
      'Cannabis': 'grass',
      'Alcohol': 'local_bar',
    };

    for (final entry in cases.entries) {
      expect(
        CategoryVisuals.suggestIcon(entry.key),
        entry.value,
        reason: entry.key,
      );
      expect(
        CategoryVisuals.icon(entry.value),
        isNot(CategoryVisuals.fallbackIcon),
        reason: '${entry.value} must be included in the app icon catalog',
      );
    }
  });

  test('unknown text uses the generic editable default', () {
    expect(CategoryVisuals.suggestIcon('Friday fund'), 'category');
  });
}
