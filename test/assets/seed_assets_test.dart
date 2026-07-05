import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category seeds cover the plan taxonomy', () {
    final categories = _readJsonList('assets/seed/categories.json');
    final byId = {
      for (final category in categories) category['id'] as String: category,
    };

    expect(byId.keys, unorderedEquals(_expectedCategoryIds));
    expect(byId['transfers']!['is_spending'], isFalse);
    expect(byId['cash_withdrawal']!['is_spending'], isFalse);
    expect(byId['income']!['is_spending'], isFalse);

    for (final category in categories) {
      expect(
        category['name'],
        isA<String>().having((name) => name, 'name', isNotEmpty),
      );
      expect(
        category['icon'],
        isA<String>().having((icon) => icon, 'icon', isNotEmpty),
      );
      expect(category['sort_order'], isA<int>());
      expect(category['is_user_created'], isFalse);
    }
  });

  test('merchant category seed map points at known categories', () {
    final categoryIds = _readJsonList(
      'assets/seed/categories.json',
    ).map((category) => category['id'] as String).toSet();
    final seedMap = _readJsonMap('assets/seed/category_seed.json');

    expect(seedMap, isNotEmpty);
    expect(seedMap.length, greaterThanOrEqualTo(12));

    for (final entry in seedMap.entries) {
      expect(entry.key.trim(), isNotEmpty);
      expect(categoryIds, contains(entry.value));
    }
  });
}

const _expectedCategoryIds = {
  'food_dining',
  'groceries',
  'transport',
  'shopping',
  'bills_utilities',
  'subscriptions',
  'rent_housing',
  'emi_loans',
  'health',
  'education',
  'entertainment',
  'travel',
  'transfers',
  'income',
  'fees_charges',
  'cash_withdrawal',
  'investments',
  'other',
};

List<Map<String, Object?>> _readJsonList(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync()) as List<Object?>;
  return decoded.cast<Map<String, Object?>>();
}

Map<String, String> _readJsonMap(String path) {
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return decoded.cast<String, String>();
}
