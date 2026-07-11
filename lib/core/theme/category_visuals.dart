import 'package:flutter/material.dart';

class CategoryIconOption {
  const CategoryIconOption(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

/// Maps category seed data (assets/seed/categories.json) to visual identity:
/// a Material icon and a stable per-category hue.
///
/// Rules (docs/design-system.md §6):
/// - Icon names in the seed JSON are Material icon identifiers; unknown or
///   user-created values fall back to [fallbackIcon].
/// - Category colors are fixed assignments, not derived from theme — a
///   category keeps its hue in both themes so users build recognition.
/// - Use [color] at full strength for icons/rings only; for backgrounds use
///   `color.withValues(alpha: 0.15)`.
abstract final class CategoryVisuals {
  static const fallbackIcon = Icons.category_outlined;
  static const fallbackColor = Color(0xFF94A3B8); // neutral slate

  /// Material icon for a seed `icon` identifier.
  static IconData icon(String? name) => _icons[name] ?? fallbackIcon;

  /// Fixed icon choices available to user-created categories.
  static const iconOptions = <CategoryIconOption>[
    CategoryIconOption('category', 'General', Icons.category),
    CategoryIconOption('smoking_rooms', 'Smoking', Icons.smoking_rooms),
    CategoryIconOption('swap_horiz', 'Transfer', Icons.swap_horiz),
    CategoryIconOption('medical_services', 'Health', Icons.medical_services),
    CategoryIconOption('home', 'Home', Icons.home),
    CategoryIconOption('content_cut', 'Personal care', Icons.content_cut),
    CategoryIconOption('local_cafe', 'Tea & coffee', Icons.local_cafe),
    CategoryIconOption('show_chart', 'Mutual funds', Icons.show_chart),
    CategoryIconOption(
      'currency_exchange',
      'Redemption',
      Icons.currency_exchange,
    ),
    CategoryIconOption('two_wheeler', 'Bike', Icons.two_wheeler),
    CategoryIconOption('wifi', 'Wi-Fi', Icons.wifi),
    CategoryIconOption('phone_android', 'Mobile recharge', Icons.phone_android),
    CategoryIconOption('smart_toy', 'AI subscription', Icons.smart_toy),
    CategoryIconOption('payments', 'Salary', Icons.payments),
    CategoryIconOption(
      'account_balance_wallet',
      'Dividend',
      Icons.account_balance_wallet,
    ),
    CategoryIconOption('candlestick_chart', 'Stocks', Icons.candlestick_chart),
    CategoryIconOption('grass', 'Cannabis', Icons.grass),
    CategoryIconOption('local_bar', 'Alcohol', Icons.local_bar),
    CategoryIconOption('restaurant', 'Food', Icons.restaurant),
    CategoryIconOption('shopping_bag', 'Shopping', Icons.shopping_bag),
    CategoryIconOption('subscriptions', 'Subscription', Icons.subscriptions),
    CategoryIconOption('school', 'Education', Icons.school),
    CategoryIconOption('flight', 'Travel', Icons.flight),
    CategoryIconOption('directions_car', 'Transport', Icons.directions_car),
  ];

  /// Suggests one curated icon from the category name, entirely on-device.
  ///
  /// Phrase-specific rules run before broad keywords. Unknown names retain the
  /// generic category icon and users can always override the suggestion.
  static String suggestIcon(String name) {
    final value =
        name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    bool hasAny(Iterable<String> terms) =>
        terms.any((term) => value.contains(term));
    final transferAction = hasAny(const ['transfer', 'send', 'allowance']);
    final familyTarget = hasAny(const ['wife', 'husband', 'family']);

    if (hasAny(const ['cigarette', 'tobacco', 'smoke', 'smoking'])) {
      return 'smoking_rooms';
    }
    if (transferAction && familyTarget) return 'swap_horiz';
    if (hasAny(const ['doctor', 'medicine', 'medical', 'pharmacy'])) {
      return 'medical_services';
    }
    if (hasAny(const ['rent', 'landlord', 'housing'])) return 'home';
    if (hasAny(const ['salon', 'haircut', 'grooming'])) return 'content_cut';
    if (hasAny(const ['mutual fund', 'mutualfund'])) return 'show_chart';
    if (hasAny(const ['redemption', 'redeem'])) return 'currency_exchange';
    if (value.contains('bike') && value.contains('service')) {
      return 'two_wheeler';
    }
    if (hasAny(const ['wifi', 'wi fi', 'broadband'])) return 'wifi';
    if (value.contains('mobile') &&
        hasAny(const ['recharge', 'payment', 'bill'])) {
      return 'phone_android';
    }
    if (hasAny(const ['claude', 'codex']) &&
        hasAny(const ['subscription', 'payment', 'plan'])) {
      return 'smart_toy';
    }
    if (hasAny(const ['salary', 'paycheck', 'pay cheque'])) return 'payments';
    if (hasAny(const ['dividend'])) return 'account_balance_wallet';
    if (hasAny(const ['stocks', 'stock market', 'equity'])) {
      return 'candlestick_chart';
    }
    if (hasAny(const ['cannabis', 'marijuana', 'weed'])) return 'grass';
    if (hasAny(const ['alcohol', 'beer', 'wine', 'whisky', 'whiskey'])) {
      return 'local_bar';
    }
    if (hasAny(const ['investment', 'investing'])) return 'show_chart';
    if (transferAction) return 'swap_horiz';
    if (hasAny(const ['tea', 'coffee', 'cafe'])) return 'local_cafe';
    return 'category';
  }

  /// Stable hue for a category id.
  static Color color(String? categoryId) =>
      _colors[categoryId] ?? fallbackColor;

  // Icon identifiers used by assets/seed/categories.json. Const map of
  // codepoints is not tree-shake friendly for unused entries, but this set is
  // small and fixed.
  static const _icons = <String, IconData>{
    'restaurant': Icons.restaurant,
    'shopping_basket': Icons.shopping_basket,
    'directions_car': Icons.directions_car,
    'shopping_bag': Icons.shopping_bag,
    'receipt_long': Icons.receipt_long,
    'subscriptions': Icons.subscriptions,
    'home': Icons.home,
    'account_balance': Icons.account_balance,
    'local_hospital': Icons.local_hospital,
    'school': Icons.school,
    'theaters': Icons.theaters,
    'flight': Icons.flight,
    'swap_horiz': Icons.swap_horiz,
    'payments': Icons.payments,
    'request_quote': Icons.request_quote,
    'atm': Icons.atm,
    'trending_up': Icons.trending_up,
    'category': Icons.category,
    'smoking_rooms': Icons.smoking_rooms,
    'medical_services': Icons.medical_services,
    'content_cut': Icons.content_cut,
    'local_cafe': Icons.local_cafe,
    'show_chart': Icons.show_chart,
    'currency_exchange': Icons.currency_exchange,
    'two_wheeler': Icons.two_wheeler,
    'wifi': Icons.wifi,
    'phone_android': Icons.phone_android,
    'smart_toy': Icons.smart_toy,
    'account_balance_wallet': Icons.account_balance_wallet,
    'candlestick_chart': Icons.candlestick_chart,
    'grass': Icons.grass,
    'local_bar': Icons.local_bar,
  };

  // One fixed hue per seed category; hues spread across the wheel so adjacent
  // dashboard segments stay distinguishable. Chosen for >=3:1 contrast as
  // icon-on-dark-surface and legibility at 0.15 alpha as tile background.
  static const _colors = <String, Color>{
    'food_dining': Color(0xFFF97316), // orange
    'groceries': Color(0xFF84CC16), // lime
    'transport': Color(0xFF38BDF8), // sky
    'shopping': Color(0xFFE879F9), // fuchsia
    'bills_utilities': Color(0xFFFACC15), // yellow
    'subscriptions': Color(0xFFA78BFA), // violet
    'rent_housing': Color(0xFF2DD4BF), // teal
    'emi_loans': Color(0xFFFB7185), // rose
    'health': Color(0xFF4ADE80), // green
    'education': Color(0xFF60A5FA), // blue
    'entertainment': Color(0xFFF472B6), // pink
    'travel': Color(0xFF22D3EE), // cyan
    'transfers': Color(0xFF94A3B8), // slate (excluded from spending)
    'income': Color(0xFF34D399), // emerald (aligns with credit)
    'fees_charges': Color(0xFFF59E0B), // amber (always surfaced in insights)
    'cash_withdrawal': Color(0xFFA8A29E), // stone
    'investments': Color(0xFFE8B54D), // brand gold
    'other': Color(0xFF9CA3AF), // gray
  };
}
