import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';

void main() {
  test('suggests curated icons for requested category phrases', () {
    const cases = {
      'Cigarette': 'smoking_rooms',
      'Tobacco': 'smoking_rooms',
      'Smoke': 'smoking_rooms',
      'JSON (Pet dog)': 'pets',
      'Transfer to Wife': 'favorite',
      'Send family allowance to husband': 'favorite',
      'Doctor visit': 'medical_services',
      'Medicine from pharmacy': 'medical_services',
      'House rent to landlord': 'house',
      'Housing': 'home',
      'Salon haircut and grooming': 'face_retouching_natural',
      'Tea + Cigarette': 'emoji_food_beverage',
      'Mutual fund investment': 'show_chart',
      'Redemption': 'currency_exchange',
      'Bike service': 'two_wheeler',
      'Bike petrol': 'local_gas_station',
      'WiFi payment': 'wifi',
      'Mobile recharge': 'phone_android',
      'Claude subscription payment': 'psychology_alt',
      'Codex subscription payment': 'terminal',
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

  test('requested personal categories receive distinct symbols and colors', () {
    const names = [
      'Tea & Cigarette',
      'JSON (Pet dog)',
      'Transfer to wife',
      'Grooming',
      'Bike Petrol',
      'House Rent',
      'Claude Subscription',
      'Codex Subscription',
    ];
    final icons = names.map(CategoryVisuals.suggestIcon).toSet();

    expect(icons, hasLength(names.length));
    expect(
      CategoryVisuals.color('subscriptions_claude'),
      CategoryVisuals.color('subscriptions'),
    );
  });
}
