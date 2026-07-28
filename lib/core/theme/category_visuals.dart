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
  static IconData icon(String? name) => iconFor(iconName: name);

  /// Resolves the Material icon for an explicit [iconName] or falls back to
  /// the icon mapped from [categoryId].
  static IconData iconFor({String? iconName, String? categoryId}) {
    if (iconName != null && _icons.containsKey(iconName)) {
      return _icons[iconName]!;
    }
    if (categoryId != null) {
      final exact = _categoryDefaultIcons[categoryId];
      if (exact != null) return exact;
      for (final entry in _categoryIconPrefixes.entries) {
        if (categoryId.startsWith(entry.key)) return entry.value;
      }
    }
    return _icons[iconName] ?? fallbackIcon;
  }

  static const _categoryDefaultIcons = <String, IconData>{
    'food_dining': Icons.restaurant,
    'groceries': Icons.local_grocery_store,
    'transport': Icons.directions_car,
    'shopping': Icons.shopping_bag,
    'bills_utilities': Icons.receipt_long,
    'subscriptions': Icons.subscriptions,
    'rent_housing': Icons.home,
    'emi_loans': Icons.credit_card,
    'health': Icons.local_hospital,
    'education': Icons.school,
    'entertainment': Icons.theaters,
    'travel': Icons.flight,
    'transfers': Icons.swap_horiz,
    'income': Icons.payments,
    'fees_charges': Icons.request_quote,
    'cash_withdrawal': Icons.atm,
    'investments': Icons.trending_up,
    'other': Icons.category,
  };

  static const _categoryIconPrefixes = <String, IconData>{
    'food_': Icons.restaurant,
    'groceries_': Icons.local_grocery_store,
    'transport_': Icons.directions_car,
    'shopping_': Icons.shopping_bag,
    'bills_': Icons.receipt_long,
    'subscriptions_': Icons.subscriptions,
    'rent_': Icons.home,
    'emi_': Icons.credit_card,
    'health_': Icons.local_hospital,
    'education_': Icons.school,
    'entertainment_': Icons.theaters,
    'travel_': Icons.flight,
    'transfers_': Icons.swap_horiz,
    'income_': Icons.payments,
    'fees_': Icons.request_quote,
    'investments_': Icons.trending_up,
    'other_': Icons.category,
  };

  /// Fixed icon choices available to user-created categories.
  static const iconOptions = <CategoryIconOption>[
    CategoryIconOption('category', 'General', Icons.category),
    CategoryIconOption(
      'emoji_food_beverage',
      'Tea & cigarette',
      Icons.emoji_food_beverage,
    ),
    CategoryIconOption('pets', 'Pet care', Icons.pets),
    CategoryIconOption('favorite', 'Family transfer', Icons.favorite),
    CategoryIconOption(
      'face_retouching_natural',
      'Grooming',
      Icons.face_retouching_natural,
    ),
    CategoryIconOption(
      'local_gas_station',
      'Bike petrol',
      Icons.local_gas_station,
    ),
    CategoryIconOption('house', 'House rent', Icons.house),
    CategoryIconOption(
      'psychology_alt',
      'Claude subscription',
      Icons.psychology_alt,
    ),
    CategoryIconOption('terminal', 'Codex subscription', Icons.terminal),
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
    CategoryIconOption('subway', 'Metro', Icons.subway),
    CategoryIconOption('local_taxi', 'Cab', Icons.local_taxi),
    CategoryIconOption(
      'electric_rickshaw',
      'Auto rickshaw',
      Icons.electric_rickshaw,
    ),
    CategoryIconOption('directions_bus', 'Bus', Icons.directions_bus),
    CategoryIconOption('train', 'Train', Icons.train),
    CategoryIconOption('local_parking', 'Parking', Icons.local_parking),
    CategoryIconOption('toll', 'Toll', Icons.toll),
    CategoryIconOption(
      'delivery_dining',
      'Food delivery',
      Icons.delivery_dining,
    ),
    CategoryIconOption('lunch_dining', 'Lunch', Icons.lunch_dining),
    CategoryIconOption(
      'local_grocery_store',
      'Groceries',
      Icons.local_grocery_store,
    ),
    CategoryIconOption('shopping_cart', 'Quick commerce', Icons.shopping_cart),
    CategoryIconOption('electric_bolt', 'Electricity', Icons.electric_bolt),
    CategoryIconOption('water_drop', 'Water bill', Icons.water_drop),
    CategoryIconOption('propane', 'Cooking gas', Icons.propane),
    CategoryIconOption('tv', 'DTH & OTT', Icons.tv),
    CategoryIconOption('credit_card', 'Credit card', Icons.credit_card),
    CategoryIconOption('apartment', 'Society charges', Icons.apartment),
    CategoryIconOption(
      'cleaning_services',
      'House help',
      Icons.cleaning_services,
    ),
    CategoryIconOption('handyman', 'Home repair', Icons.handyman),
    CategoryIconOption(
      'local_laundry_service',
      'Laundry',
      Icons.local_laundry_service,
    ),
    CategoryIconOption('fitness_center', 'Gym', Icons.fitness_center),
    CategoryIconOption('sports_cricket', 'Sports', Icons.sports_cricket),
    CategoryIconOption('medication', 'Pharmacy', Icons.medication),
    CategoryIconOption('child_care', 'Child care', Icons.child_care),
    CategoryIconOption('laptop_mac', 'Online services', Icons.laptop_mac),
    CategoryIconOption('hotel', 'Hotel', Icons.hotel),
    CategoryIconOption('shield', 'Insurance', Icons.shield),
    CategoryIconOption('savings', 'Savings', Icons.savings),
    CategoryIconOption('currency_rupee', 'Tax & money', Icons.currency_rupee),
    CategoryIconOption(
      'volunteer_activism',
      'Donation',
      Icons.volunteer_activism,
    ),
    CategoryIconOption('temple_hindu', 'Religious', Icons.temple_hindu),
    CategoryIconOption('redeem', 'Gifts', Icons.redeem),
    CategoryIconOption('movie', 'Movies', Icons.movie),
    CategoryIconOption('music_note', 'Music', Icons.music_note),
    CategoryIconOption('cloud', 'Cloud storage', Icons.cloud),
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

    if (hasAny(const ['json', 'pet dog', 'pet care', 'veterinary', 'vet'])) {
      return 'pets';
    }
    if (hasAny(const ['tea']) &&
        hasAny(const ['cigarette', 'tobacco', 'smoke', 'smoking'])) {
      return 'emoji_food_beverage';
    }
    if (hasAny(const ['cigarette', 'tobacco', 'smoke', 'smoking'])) {
      return 'smoking_rooms';
    }
    if (transferAction && familyTarget) return 'favorite';
    if (hasAny(const ['doctor', 'medicine', 'medical', 'pharmacy'])) {
      return 'medical_services';
    }
    if (hasAny(const ['house rent', 'rent to landlord'])) return 'house';
    if (hasAny(const ['rent', 'landlord', 'housing'])) return 'home';
    if (hasAny(const ['salon', 'haircut', 'grooming'])) {
      return 'face_retouching_natural';
    }
    if (hasAny(const ['mutual fund', 'mutualfund'])) return 'show_chart';
    if (hasAny(const ['redemption', 'redeem'])) return 'currency_exchange';
    if (value.contains('bike') &&
        hasAny(const ['petrol', 'fuel', 'gas station'])) {
      return 'local_gas_station';
    }
    if (value.contains('bike') && value.contains('service')) {
      return 'two_wheeler';
    }
    if (hasAny(const ['wifi', 'wi fi', 'broadband'])) return 'wifi';
    if (value.contains('mobile') &&
        hasAny(const ['recharge', 'payment', 'bill'])) {
      return 'phone_android';
    }
    if (value.contains('claude') &&
        hasAny(const ['subscription', 'payment', 'plan'])) {
      return 'psychology_alt';
    }
    if (value.contains('codex') &&
        hasAny(const ['subscription', 'payment', 'plan'])) {
      return 'terminal';
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
  static Color color(String? categoryId) {
    final exact = _colors[categoryId];
    if (exact != null) return exact;
    if (categoryId == null) return fallbackColor;
    for (final entry in _colorPrefixes.entries) {
      if (categoryId.startsWith(entry.key)) return entry.value;
    }
    return fallbackColor;
  }

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
    'emoji_food_beverage': Icons.emoji_food_beverage,
    'pets': Icons.pets,
    'favorite': Icons.favorite,
    'face_retouching_natural': Icons.face_retouching_natural,
    'local_gas_station': Icons.local_gas_station,
    'house': Icons.house,
    'psychology_alt': Icons.psychology_alt,
    'terminal': Icons.terminal,
    'subway': Icons.subway,
    'local_taxi': Icons.local_taxi,
    'electric_rickshaw': Icons.electric_rickshaw,
    'directions_bus': Icons.directions_bus,
    'train': Icons.train,
    'local_parking': Icons.local_parking,
    'toll': Icons.toll,
    'delivery_dining': Icons.delivery_dining,
    'lunch_dining': Icons.lunch_dining,
    'local_grocery_store': Icons.local_grocery_store,
    'shopping_cart': Icons.shopping_cart,
    'electric_bolt': Icons.electric_bolt,
    'water_drop': Icons.water_drop,
    'propane': Icons.propane,
    'tv': Icons.tv,
    'credit_card': Icons.credit_card,
    'apartment': Icons.apartment,
    'cleaning_services': Icons.cleaning_services,
    'handyman': Icons.handyman,
    'local_laundry_service': Icons.local_laundry_service,
    'fitness_center': Icons.fitness_center,
    'sports_cricket': Icons.sports_cricket,
    'medication': Icons.medication,
    'child_care': Icons.child_care,
    'laptop_mac': Icons.laptop_mac,
    'hotel': Icons.hotel,
    'shield': Icons.shield,
    'savings': Icons.savings,
    'currency_rupee': Icons.currency_rupee,
    'volunteer_activism': Icons.volunteer_activism,
    'temple_hindu': Icons.temple_hindu,
    'redeem': Icons.redeem,
    'movie': Icons.movie,
    'music_note': Icons.music_note,
    'cloud': Icons.cloud,
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
    'recharge': Color(0xFFFACC15), // maps logically to bills_utilities yellow
    'other': Color(0xFF9CA3AF), // gray
  };

  static const _colorPrefixes = <String, Color>{
    'food_': Color(0xFFF97316),
    'groceries_': Color(0xFF84CC16),
    'transport_': Color(0xFF38BDF8),
    'shopping_': Color(0xFFE879F9),
    'bills_': Color(0xFFFACC15),
    'subscriptions_': Color(0xFFA78BFA),
    'rent_': Color(0xFF2DD4BF),
    'emi_': Color(0xFFFB7185),
    'health_': Color(0xFF4ADE80),
    'education_': Color(0xFF60A5FA),
    'entertainment_': Color(0xFFF472B6),
    'travel_': Color(0xFF22D3EE),
    'transfers_': Color(0xFF94A3B8),
    'income_': Color(0xFF34D399),
    'fees_': Color(0xFFF59E0B),
    'investments_': Color(0xFFE8B54D),
    'other_': Color(0xFF9CA3AF),
  };
}
