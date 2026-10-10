import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';

void main() {
  late SeedCategoryMap map;
  late Set<String> categoryIds;

  setUpAll(() {
    map = SeedCategoryMap.fromJson(
      File('assets/seed/category_seed.json').readAsStringSync(),
    );
    categoryIds = {
      for (final row in (jsonDecode(
        File('assets/seed/categories.json').readAsStringSync(),
      ) as List<Object?>)
          .cast<Map<String, Object?>>())
        row['id']! as String,
    };
  });

  test('every seed target is a bundled category id', () {
    for (final id in map.categoryIds) {
      expect(categoryIds, contains(id));
    }
  });

  group('representative merchants', () {
    const cases = <String, String>{
      'CHAAYOS CAFE PVT LTD': 'food_tea_chai_stall',
      'Chai Point': 'food_tea_chai_stall',
      'STARBUCKS COFFEE': 'food_coffee',
      'SWIGGY': 'food_delivery',
      'zomato@hdfcbank': 'food_delivery',
      'BigBasket Innovative Retail': 'groceries_online_grocery',
      'bigbasket.payu@hdfcbank': 'groceries_online_grocery',
      'BLINKIT': 'groceries_quick_commerce',
      'ZEPTO MARKETPLACE': 'groceries_quick_commerce',
      'SWIGGY INSTAMART': 'groceries_quick_commerce',
      'JIOMART': 'groceries_online_grocery',
      'IOCL PETROL PUMP': 'vehicle_own_fuel_petrol_diesel',
      'Indian Oil Corp': 'vehicle_own_fuel_petrol_diesel',
      'HPCL': 'vehicle_own_fuel_petrol_diesel',
      'BPCL FUEL': 'vehicle_own_fuel_petrol_diesel',
      'SHELL INDIA': 'vehicle_own_fuel_petrol_diesel',
      'PAYTM FASTAG RECHARGE': 'vehicle_own_toll_fastag',
      'NETC FASTAG': 'vehicle_own_toll_fastag',
      'RAPIDO': 'vehicle_rental_bike_taxi',
      'UBER INDIA': 'transport_cab_auto',
      'OLACABS': 'vehicle_rental_cab',
      'ZOOMCAR INDIA': 'vehicle_rental_self_drive',
      'REVV': 'vehicle_rental_self_drive',
      'OYO ROOMS': 'travel_hotels',
      'Airbnb Payments': 'travel_stay_homestay',
      'MAKEMYTRIP INDIA': 'travel',
      'GOIBIBO': 'travel',
      'IRCTC': 'travel_trains',
      'REDBUS': 'travel_intercity_bus',
      'KARNATAKA STATE BEVERAGES CORP': 'alcohol_tobacco_liquor_store',
      'Sai Wine Shop': 'alcohol_tobacco_liquor_store',
      'TASMAC': 'alcohol_tobacco_liquor_store',
      'Gold Flake Cigarettes': 'alcohol_tobacco_cigarettes',
      'Ram Paan Shop': 'alcohol_tobacco_paan',
      'SUPERTAILS': 'pets_food',
      'Heads Up For Tails': 'pets_food',
      'NYKAA ECOMMERCE': 'personal_care_cosmetics_skincare',
      'Urban Company Salon': 'personal_care_salon_barber',
      'URBAN COMPANY': 'home_household_home_services',
      'PHARMEASY': 'health_pharmacy',
      'LAL PATHLABS': 'health_diagnostics',
      'MYNTRA DESIGNS': 'shopping_clothing',
      'AMAZON PAY': 'shopping',
      'COINSWITCH KUBER': 'investments_crypto',
      'TIRUPATI DEVASTHANAM': 'gifts_donations_temple',
    };
    cases.forEach((text, expected) {
      test('$text -> $expected', () {
        expect(map.categoryFor(text), expected);
      });
    });
  });

  group('legacy mappings are preserved', () {
    const cases = <String, String>{
      'NETFLIX': 'subscriptions_ott',
      'hdfc ergo general': 'health_insurance',
      'JIO FIBER': 'bills_broadband_wifi',
      'JIOFIBER': 'bills_broadband_wifi',
      'JIO PREPAID': 'bills_mobile_recharge',
      'BSNL BROADBAND': 'bills_broadband_wifi',
      'AMZN MKTP': 'shopping',
      'PETROL PUMP': 'transport_bike_petrol',
      'OLA': 'transport_cab_auto',
      'LIC OF INDIA': 'investments',
    };
    cases.forEach((text, expected) {
      test('$text -> $expected', () {
        expect(map.categoryFor(text), expected);
      });
    });
  });

  group('no fuzzy or substring misfiling (ADR 0011)', () {
    for (final text in const [
      'Public Works Dept',
      'COCA COLA INDIA',
      'Ramesh Kumar',
      'ramesh.kumar@okhdfcbank',
      'priya@ybl',
      '9876543210@paytm',
      'Pearlshell Traders',
      'INOX AIR PRODUCTS',
      'Mohan Dental Stores Pvt',
      'Unknown Vendor',
    ]) {
      test('$text is left unmapped or not misfiled', () {
        final result = map.categoryFor(text);
        if (text.contains('Dental')) {
          // A real dental token is allowed to map; nothing else may.
          expect(result, 'health_dental');
        } else {
          expect(result, isNull);
        }
      });
    }

    test('personal VPAs alone never map to a transfer category', () {
      for (final vpa in const ['rahul.sharma@okaxis', 'anita@oksbi']) {
        expect(map.categoryFor(vpa), isNull);
      }
      for (final id in map.categoryIds) {
        expect(id, isNot(startsWith('transfers')));
      }
    });
  });

  group('matching rules', () {
    final small = SeedCategoryMap({
      'lic': 'investments',
      'hdfc': 'fees',
      'hdfc ergo': 'insurance',
      'swiggy': 'food',
    });

    test('short keys need token boundaries on both sides', () {
      expect(small.categoryFor('LIC PREMIUM'), 'investments');
      expect(small.categoryFor('lic.premium@sbi'), 'investments');
      expect(small.categoryFor('PUBLIC SERVICE'), isNull);
      expect(small.categoryFor('LICENSE FEE'), isNull);
    });

    test('long keys may prefix a token but not sit inside one', () {
      expect(small.categoryFor('SWIGGYINSTAMART'), 'food');
      expect(small.categoryFor('XSWIGGY'), isNull);
    });

    test('punctuation and spacing are normalised; longest key wins', () {
      expect(small.categoryFor('HDFC-ERGO  General'), 'insurance');
      expect(small.categoryFor('HDFC BANK'), 'fees');
    });
  });
}
