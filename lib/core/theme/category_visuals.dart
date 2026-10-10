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

  /// Whether [name] is a registered seed/user icon identifier.
  static bool hasIcon(String? name) => _icons.containsKey(name);

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
    'alcohol_tobacco': Icons.local_bar_rounded,
    'personal_care': Icons.face_retouching_natural,
    'pets': Icons.pets,
    'vehicle_own': Icons.directions_car,
    'vehicle_rental': Icons.car_rental_rounded,
    'public_transport': Icons.directions_transit_rounded,
    'home_household': Icons.cleaning_services,
    'kids_family': Icons.family_restroom_rounded,
    'events_celebrations': Icons.celebration_rounded,
    'gifts_donations': Icons.card_giftcard_rounded,
    'insurance': Icons.shield,
    'govt_legal': Icons.account_balance,
    'business': Icons.business_center_rounded,
    'lending_borrowing': Icons.handshake_rounded,
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
    'alcohol_tobacco_': Icons.local_bar_rounded,
    'personal_care_': Icons.face_retouching_natural,
    'pets_': Icons.pets,
    'vehicle_own_': Icons.directions_car,
    'vehicle_rental_': Icons.car_rental_rounded,
    'public_transport_': Icons.directions_transit_rounded,
    'home_household_': Icons.cleaning_services,
    'kids_family_': Icons.family_restroom_rounded,
    'events_celebrations_': Icons.celebration_rounded,
    'gifts_donations_': Icons.card_giftcard_rounded,
    'insurance_': Icons.shield,
    'govt_legal_': Icons.account_balance,
    'business_': Icons.business_center_rounded,
    'lending_borrowing_': Icons.handshake_rounded,
    'cash_': Icons.atm,
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
    // Taxonomy expansion (seed v2) — Rounded variants for new categories.
    'accessibility_new_rounded': Icons.accessibility_new_rounded,
    'add_road_rounded': Icons.add_road_rounded,
    'add_shopping_cart_rounded': Icons.add_shopping_cart_rounded,
    'airport_shuttle_rounded': Icons.airport_shuttle_rounded,
    'approval_rounded': Icons.approval_rounded,
    'apps_rounded': Icons.apps_rounded,
    'assignment_return_rounded': Icons.assignment_return_rounded,
    'assignment_rounded': Icons.assignment_rounded,
    'assignment_turned_in_rounded': Icons.assignment_turned_in_rounded,
    'attractions_rounded': Icons.attractions_rounded,
    'baby_changing_station_rounded': Icons.baby_changing_station_rounded,
    'backpack_rounded': Icons.backpack_rounded,
    'badge_rounded': Icons.badge_rounded,
    'bakery_dining_rounded': Icons.bakery_dining_rounded,
    'balance_rounded': Icons.balance_rounded,
    'bed_rounded': Icons.bed_rounded,
    'biotech_rounded': Icons.biotech_rounded,
    'brush_rounded': Icons.brush_rounded,
    'build_rounded': Icons.build_rounded,
    'business_center_rounded': Icons.business_center_rounded,
    'business_rounded': Icons.business_rounded,
    'cake_rounded': Icons.cake_rounded,
    'calculate_rounded': Icons.calculate_rounded,
    'call_made_rounded': Icons.call_made_rounded,
    'call_received_rounded': Icons.call_received_rounded,
    'campaign_rounded': Icons.campaign_rounded,
    'car_rental_rounded': Icons.car_rental_rounded,
    'car_repair_rounded': Icons.car_repair_rounded,
    'card_giftcard_rounded': Icons.card_giftcard_rounded,
    'card_membership_rounded': Icons.card_membership_rounded,
    'celebration_rounded': Icons.celebration_rounded,
    'chair_rounded': Icons.chair_rounded,
    'child_friendly_rounded': Icons.child_friendly_rounded,
    'co_present_rounded': Icons.co_present_rounded,
    'coffee_rounded': Icons.coffee_rounded,
    'construction_rounded': Icons.construction_rounded,
    'contactless_rounded': Icons.contactless_rounded,
    'cookie_rounded': Icons.cookie_rounded,
    'cottage_rounded': Icons.cottage_rounded,
    'credit_score_rounded': Icons.credit_score_rounded,
    'currency_bitcoin_rounded': Icons.currency_bitcoin_rounded,
    'description_rounded': Icons.description_rounded,
    'diamond_rounded': Icons.diamond_rounded,
    'directions_ferry_rounded': Icons.directions_ferry_rounded,
    'directions_transit_rounded': Icons.directions_transit_rounded,
    'diversity_1_rounded': Icons.diversity_1_rounded,
    'domain_rounded': Icons.domain_rounded,
    'dry_rounded': Icons.dry_rounded,
    'edit_note_rounded': Icons.edit_note_rounded,
    'egg_alt_rounded': Icons.egg_alt_rounded,
    'elderly_rounded': Icons.elderly_rounded,
    'emoji_events_rounded': Icons.emoji_events_rounded,
    'ev_station_rounded': Icons.ev_station_rounded,
    'face_3_rounded': Icons.face_3_rounded,
    'face_rounded': Icons.face_rounded,
    'family_restroom_rounded': Icons.family_restroom_rounded,
    'fastfood_rounded': Icons.fastfood_rounded,
    'festival_rounded': Icons.festival_rounded,
    'format_paint_rounded': Icons.format_paint_rounded,
    'gas_meter_rounded': Icons.gas_meter_rounded,
    'gavel_rounded': Icons.gavel_rounded,
    'grain_rounded': Icons.grain_rounded,
    'group_add_rounded': Icons.group_add_rounded,
    'groups_rounded': Icons.groups_rounded,
    'handshake_rounded': Icons.handshake_rounded,
    'health_and_safety_rounded': Icons.health_and_safety_rounded,
    'help_outline_rounded': Icons.help_outline_rounded,
    'hiking_rounded': Icons.hiking_rounded,
    'home_repair_service_rounded': Icons.home_repair_service_rounded,
    'house_siding_rounded': Icons.house_siding_rounded,
    'icecream_rounded': Icons.icecream_rounded,
    'inventory_2_rounded': Icons.inventory_2_rounded,
    'inventory_rounded': Icons.inventory_rounded,
    'kitchen_rounded': Icons.kitchen_rounded,
    'landscape_rounded': Icons.landscape_rounded,
    'library_books_rounded': Icons.library_books_rounded,
    'liquor_rounded': Icons.liquor_rounded,
    'live_tv_rounded': Icons.live_tv_rounded,
    'local_bar_rounded': Icons.local_bar_rounded,
    'local_car_wash_rounded': Icons.local_car_wash_rounded,
    'local_dining_rounded': Icons.local_dining_rounded,
    'local_drink_rounded': Icons.local_drink_rounded,
    'local_florist_rounded': Icons.local_florist_rounded,
    'local_shipping_rounded': Icons.local_shipping_rounded,
    'lock_open_rounded': Icons.lock_open_rounded,
    'lock_rounded': Icons.lock_rounded,
    'loyalty_rounded': Icons.loyalty_rounded,
    'luggage_rounded': Icons.luggage_rounded,
    'menu_book_rounded': Icons.menu_book_rounded,
    'military_tech_rounded': Icons.military_tech_rounded,
    'monitor_heart_rounded': Icons.monitor_heart_rounded,
    'moped_rounded': Icons.moped_rounded,
    'more_horiz_rounded': Icons.more_horiz_rounded,
    'newspaper_rounded': Icons.newspaper_rounded,
    'nightlife_rounded': Icons.nightlife_rounded,
    'palette_rounded': Icons.palette_rounded,
    'people_rounded': Icons.people_rounded,
    'percent_rounded': Icons.percent_rounded,
    'phonelink_lock_rounded': Icons.phonelink_lock_rounded,
    'plumbing_rounded': Icons.plumbing_rounded,
    'point_of_sale_rounded': Icons.point_of_sale_rounded,
    'policy_rounded': Icons.policy_rounded,
    'precision_manufacturing_rounded': Icons.precision_manufacturing_rounded,
    'price_check_rounded': Icons.price_check_rounded,
    'psychology_rounded': Icons.psychology_rounded,
    'ramen_dining_rounded': Icons.ramen_dining_rounded,
    'real_estate_agent_rounded': Icons.real_estate_agent_rounded,
    'report_rounded': Icons.report_rounded,
    'request_page_rounded': Icons.request_page_rounded,
    'restaurant_menu_rounded': Icons.restaurant_menu_rounded,
    'schedule_send_rounded': Icons.schedule_send_rounded,
    'security_rounded': Icons.security_rounded,
    'self_improvement_rounded': Icons.self_improvement_rounded,
    'set_meal_rounded': Icons.set_meal_rounded,
    'sim_card_rounded': Icons.sim_card_rounded,
    'smartphone_rounded': Icons.smartphone_rounded,
    'smoke_free_rounded': Icons.smoke_free_rounded,
    'smoking_rooms_rounded': Icons.smoking_rooms_rounded,
    'soap_rounded': Icons.soap_rounded,
    'soup_kitchen_rounded': Icons.soup_kitchen_rounded,
    'spa_rounded': Icons.spa_rounded,
    'sports_bar_rounded': Icons.sports_bar_rounded,
    'sports_esports_rounded': Icons.sports_esports_rounded,
    'sports_gymnastics_rounded': Icons.sports_gymnastics_rounded,
    'sports_soccer_rounded': Icons.sports_soccer_rounded,
    'store_mall_directory_rounded': Icons.store_mall_directory_rounded,
    'storefront_rounded': Icons.storefront_rounded,
    'sync_alt_rounded': Icons.sync_alt_rounded,
    'takeout_dining_rounded': Icons.takeout_dining_rounded,
    'tire_repair_rounded': Icons.tire_repair_rounded,
    'tour_rounded': Icons.tour_rounded,
    'toys_rounded': Icons.toys_rounded,
    'tune_rounded': Icons.tune_rounded,
    'vaccines_rounded': Icons.vaccines_rounded,
    'vaping_rooms_rounded': Icons.vaping_rooms_rounded,
    'verified_user_rounded': Icons.verified_user_rounded,
    'villa_rounded': Icons.villa_rounded,
    'visibility_rounded': Icons.visibility_rounded,
    'vpn_key_rounded': Icons.vpn_key_rounded,
    'weekend_rounded': Icons.weekend_rounded,
    'wine_bar_rounded': Icons.wine_bar_rounded,
    'woman_rounded': Icons.woman_rounded,
    'work_rounded': Icons.work_rounded,
    'yard_rounded': Icons.yard_rounded,
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
    'alcohol_tobacco': Color(0xFFC084FC), // purple
    'personal_care': Color(0xFFFB923C), // light orange
    'pets': Color(0xFFA3E635), // yellow-green
    'vehicle_own': Color(0xFF0EA5E9), // blue
    'vehicle_rental': Color(0xFF7DD3FC), // light blue
    'public_transport': Color(0xFF0284C7), // deep sky
    'home_household': Color(0xFF5EEAD4), // light teal
    'kids_family': Color(0xFFFDA4AF), // light rose
    'events_celebrations': Color(0xFFE11D48), // crimson
    'gifts_donations': Color(0xFFF9A8D4), // light pink
    'insurance': Color(0xFF14B8A6), // teal
    'govt_legal': Color(0xFF64748B), // blue-slate
    'business': Color(0xFF6366F1), // indigo
    'lending_borrowing': Color(0xFFB45309), // brown
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
    'alcohol_tobacco_': Color(0xFFC084FC),
    'personal_care_': Color(0xFFFB923C),
    'pets_': Color(0xFFA3E635),
    'vehicle_own_': Color(0xFF0EA5E9),
    'vehicle_rental_': Color(0xFF7DD3FC),
    'public_transport_': Color(0xFF0284C7),
    'home_household_': Color(0xFF5EEAD4),
    'kids_family_': Color(0xFFFDA4AF),
    'events_celebrations_': Color(0xFFE11D48),
    'gifts_donations_': Color(0xFFF9A8D4),
    'insurance_': Color(0xFF14B8A6),
    'govt_legal_': Color(0xFF64748B),
    'business_': Color(0xFF6366F1),
    'lending_borrowing_': Color(0xFFB45309),
    'cash_': Color(0xFFA8A29E),
  };
}
