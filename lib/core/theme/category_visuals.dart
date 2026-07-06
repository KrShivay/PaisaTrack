import 'package:flutter/material.dart';

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

  /// Stable hue for a category id.
  static Color color(String? categoryId) =>
      _colors[categoryId] ?? fallbackColor;

  /// Stable hue for a display name (e.g. `Food & Dining` -> `food_dining`).
  ///
  /// Interim path for list rows whose query carries only the category name;
  /// once `TransactionListItem` includes `category_id`/`icon`, prefer
  /// [color]/[icon] directly. User-created names fall back to neutral.
  static Color colorForName(String? name) => color(_idForName(name));

  /// Icon for a display name, same normalization as [colorForName].
  static IconData iconForName(String? name) {
    final id = _idForName(name);
    if (id == null) return fallbackIcon;
    final iconName = _seedIconByCategoryId[id];
    return _icons[iconName] ?? fallbackIcon;
  }

  /// Normalizes a seed display name to its category id: lowercase, drop
  /// punctuation, join word tokens with underscores.
  static String? _idForName(String? name) {
    if (name == null || name.isEmpty) return null;
    final tokens = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (tokens.isEmpty) return null;
    final id = tokens.join('_');
    return _colors.containsKey(id) ? id : null;
  }

  // Mirror of assets/seed/categories.json id -> icon identifier.
  static const _seedIconByCategoryId = <String, String>{
    'food_dining': 'restaurant',
    'groceries': 'shopping_basket',
    'transport': 'directions_car',
    'shopping': 'shopping_bag',
    'bills_utilities': 'receipt_long',
    'subscriptions': 'subscriptions',
    'rent_housing': 'home',
    'emi_loans': 'account_balance',
    'health': 'local_hospital',
    'education': 'school',
    'entertainment': 'theaters',
    'travel': 'flight',
    'transfers': 'swap_horiz',
    'income': 'payments',
    'fees_charges': 'request_quote',
    'cash_withdrawal': 'atm',
    'investments': 'trending_up',
    'other': 'category',
  };

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
