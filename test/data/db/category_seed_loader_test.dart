import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';
import 'package:paisatrack/data/db/database.dart';

/// Minimal bundle serving one in-memory categories asset.
class _StringBundle extends AssetBundle {
  _StringBundle(this.json);

  final String json;

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(json);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => json;

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async =>
      parser(json);
}

List<Map<String, Object?>> _readJsonList(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List<Object?>)
        .cast<Map<String, Object?>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Snapshot of the original 87-category taxonomy: these ids are referenced by
  // transactions, rules, feedback and backups and must never change.
  final legacy = _readJsonList('test/fixtures/categories_v1.json');
  final legacyIds = legacy.map((row) => row['id']! as String).toSet();
  final bundled = _readJsonList('assets/seed/categories.json');
  final bundledById = {for (final row in bundled) row['id']! as String: row};

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<Category> category(String id) =>
      (database.select(database.categories)..where((row) => row.id.equals(id)))
          .getSingle();

  Future<Category?> maybeCategory(String id) =>
      (database.select(database.categories)..where((row) => row.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertLegacyOnly() async {
    for (final row in legacy) {
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: row['id']! as String,
              name: row['name']! as String,
              parentId: Value(row['parent_id'] as String?),
              icon: row['icon']! as String,
              isSpending: row['is_spending']! as bool,
              sortOrder: row['sort_order']! as int,
              isUserCreated: row['is_user_created']! as bool,
            ),
          );
    }
  }

  group('bundled taxonomy', () {
    test('keeps every original id with its original definition', () {
      expect(legacy, hasLength(87));
      for (final row in legacy) {
        final current = bundledById[row['id']];
        expect(current, isNotNull, reason: 'missing ${row['id']}');
        for (final field in const [
          'name',
          'parent_id',
          'icon',
          'is_spending',
          'sort_order',
          'is_user_created',
        ]) {
          expect(current![field], row[field], reason: '${row['id']}.$field');
        }
        expect(current!.containsKey('since'), isFalse);
      }
    });

    test('is a two-level tree with unique ids, names and sort orders', () {
      final roots = bundled.where((row) => row['parent_id'] == null).toList();
      final subs = bundled.where((row) => row['parent_id'] != null).toList();
      expect(bundled.map((r) => r['id']).toSet(), hasLength(bundled.length));
      expect(roots.length, inInclusiveRange(30, 40));
      expect(subs.length, inInclusiveRange(200, 320));
      final rootIds = roots.map((r) => r['id']).toSet();
      for (final sub in subs) {
        expect(rootIds, contains(sub['parent_id']), reason: '${sub['id']}');
      }
      final rootOrders = roots.map((r) => r['sort_order']).toList();
      expect(rootOrders.toSet(), hasLength(roots.length));
      for (final root in roots) {
        final siblings = subs.where((s) => s['parent_id'] == root['id']);
        expect(
          siblings.map((s) => s['sort_order']).toSet(),
          hasLength(siblings.length),
          reason: 'sort_order clash under ${root['id']}',
        );
        expect(
          siblings.map((s) => (s['name']! as String).toLowerCase()).toSet(),
          hasLength(siblings.length),
          reason: 'duplicate name under ${root['id']}',
        );
      }
      for (final row in bundled) {
        expect(row['id'], matches(RegExp(r'^[a-z0-9_]+$')));
        expect((row['name']! as String).trim(), isNotEmpty);
        expect(row['is_user_created'], isFalse);
        if (!legacyIds.contains(row['id'])) expect(row['since'], 2);
      }
    });

    test('covers the requested everyday Indian spending types', () {
      const required = [
        'food_tea_chai_stall',
        'food_coffee',
        'food_street_food',
        'food_bakery_sweets',
        'food_office_canteen',
        'groceries_kirana',
        'groceries_dairy_milk',
        'groceries_meat_fish',
        'groceries_online_grocery',
        'alcohol_tobacco',
        'alcohol_tobacco_liquor_store',
        'alcohol_tobacco_bar_pub',
        'alcohol_tobacco_cigarettes',
        'alcohol_tobacco_paan',
        'alcohol_tobacco_cannabis',
        'alcohol_tobacco_vape',
        'personal_care_salon_barber',
        'personal_care_cosmetics_skincare',
        'personal_care_spa_massage',
        'pets_food',
        'pets_vet',
        'pets_boarding',
        'vehicle_own_fuel_petrol_diesel',
        'vehicle_own_ev_charging',
        'vehicle_own_cng',
        'vehicle_own_toll_fastag',
        'vehicle_own_challan_fines',
        'vehicle_rental_self_drive',
        'vehicle_rental_bike',
        'vehicle_rental_cab',
        'vehicle_rental_auto',
        'vehicle_rental_bike_taxi',
        'public_transport_metro',
        'public_transport_bus',
        'public_transport_local_train',
        'travel_flights',
        'travel_trains',
        'travel_intercity_bus',
        'travel_hotels',
        'travel_stay_homestay',
        'travel_insurance',
        'travel_visa_passport',
        'travel_forex',
        'travel_tours_activities',
        'rent_house',
        'rent_maintenance',
        'rent_deposit',
        'rent_pg_hostel',
        'health_diagnostics',
        'health_dental',
        'health_eye_care',
        'health_therapy',
        'kids_family_household_help',
        'kids_family_elder_care',
        'gifts_donations_charity',
        'gifts_donations_temple',
        'insurance_life',
        'insurance_term',
        'govt_legal',
        'business',
        'income_rent_received',
        'income_cashback',
        'income_refunds',
        'transfers_self',
        'transfers_wallet_topup',
        'investments_crypto',
        'investments_rd',
        'cash_withdrawal',
        'other',
      ];
      for (final id in required) {
        expect(bundledById, contains(id));
      }
    });

    test('is_spending semantics: transfers, income, cash, lending excluded',
        () {
      bool spending(String id) => bundledById[id]!['is_spending']! as bool;
      for (final row in bundled) {
        final id = row['id']! as String;
        final root = row['parent_id'] as String? ?? id;
        if (const {
          'transfers',
          'income',
          'cash_withdrawal',
          'lending_borrowing',
        }.contains(root)) {
          expect(spending(id), isFalse, reason: id);
        }
        // New investment holdings are not consumption (legacy investment rows
        // keep their original flag; see docs/schema.md).
        if (root == 'investments' && !legacyIds.contains(id)) {
          expect(spending(id), id == 'investments_demat_charges', reason: id);
        }
      }
      expect(spending('emi_credit_card_payment'), isFalse);
      expect(spending('emi_credit_card'), isTrue, reason: 'legacy unchanged');
      expect(spending('rent_deposit'), isFalse);
      expect(spending('income_rent_received'), isFalse);
      for (final id in const [
        'alcohol_tobacco',
        'alcohol_tobacco_cannabis',
        'pets_vet',
        'vehicle_own_fuel_petrol_diesel',
        'insurance_term',
        'govt_legal_income_tax',
        'business_travel',
        'fees_late_penalty',
        'travel_stay_homestay',
      ]) {
        expect(spending(id), isTrue, reason: id);
      }
    });

    test('every icon string resolves in CategoryVisuals', () {
      for (final row in bundled) {
        expect(
          CategoryVisuals.hasIcon(row['icon']! as String),
          isTrue,
          reason: '${row['id']} uses unregistered icon ${row['icon']}',
        );
        expect(
          CategoryVisuals.icon(row['icon']! as String),
          isNot(CategoryVisuals.fallbackIcon),
        );
      }
    });

    test('every category has a stable non-fallback colour', () {
      for (final row in bundled) {
        // Transfers deliberately share the neutral slate with the fallback.
        if ((row['id']! as String).startsWith('transfers')) continue;
        expect(
          CategoryVisuals.color(row['id']! as String),
          isNot(CategoryVisuals.fallbackColor),
          reason: row['id']! as String,
        );
      }
    });
  });

  group('seeding', () {
    test('loads bundled category seeds idempotently', () async {
      await database.seedDefaultCategories();

      final seeded = await database.select(database.categories).get();
      expect(seeded, hasLength(bundled.length));
      expect(
        seeded.map((category) => category.id),
        containsAll(const [
          'food_dining',
          'cash_withdrawal',
          'food_tea_cigarette',
          'subscriptions_claude',
          'subscriptions_codex',
          'alcohol_tobacco_cannabis',
          'pets_boarding',
        ]),
      );
      expect(
        (await category('subscriptions_claude')).parentId,
        'subscriptions',
      );
      expect((await category('alcohol_tobacco_cannabis')).name, 'Cannabis');

      await (database.update(database.categories)
            ..where((category) => category.id.equals('food_dining')))
          .write(
        const CategoriesCompanion(
          name: Value('Food I renamed'),
          icon: Value('custom_food'),
        ),
      );

      await database.seedDefaultCategories();

      expect(
        await database.select(database.categories).get(),
        hasLength(bundled.length),
      );
      final food = await category('food_dining');
      expect(food.name, 'Food I renamed');
      expect(food.icon, 'custom_food');
    });

    test(
        'existing installs receive new categories without changes to '
        'existing rows', () async {
      await insertLegacyOnly();
      await (database.update(database.categories)
            ..where((row) => row.id.equals('food_dining')))
          .write(const CategoriesCompanion(name: Value('My food')));
      await (database.update(database.categories)
            ..where((row) => row.id.equals('investments')))
          .write(const CategoriesCompanion(isSpending: Value(false)));
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: 'user_chai_1',
              name: 'My chai',
              icon: 'category',
              isSpending: true,
              sortOrder: 5000,
              isUserCreated: true,
              parentId: const Value('food_dining'),
            ),
          );
      final before = {
        for (final row in await database.select(database.categories).get())
          row.id: row,
      };

      await database.seedDefaultCategories();

      final after = {
        for (final row in await database.select(database.categories).get())
          row.id: row,
      };
      expect(after, hasLength(bundled.length + 1));
      for (final entry in before.entries) {
        expect(after[entry.key], entry.value, reason: entry.key);
      }
      expect(after['food_dining']!.name, 'My food');
      expect(after['investments']!.isSpending, isFalse);
      expect(after['pets_vet']!.parentId, 'pets');
      expect(after['alcohol_tobacco_vape']!.isSpending, isTrue);
    });

    test('a category the user deleted is not resurrected', () async {
      await database.seedDefaultCategories();
      await (database.delete(database.categories)
            ..where((row) => row.id.equals('pets_boarding')))
          .go();
      await (database.delete(database.categories)
            ..where((row) => row.id.equals('alcohol_tobacco_hookah')))
          .go();

      await database.seedDefaultCategories();
      await database.seedDefaultCategories();

      expect(await maybeCategory('pets_boarding'), isNull);
      expect(await maybeCategory('alcohol_tobacco_hookah'), isNull);
      expect(await maybeCategory('pets_vet'), isNotNull);
      expect(
        await database.select(database.categories).get(),
        hasLength(bundled.length - 2),
      );
    });

    test('a deleted new category on an upgraded install stays deleted',
        () async {
      await insertLegacyOnly();
      await database.seedDefaultCategories(); // upgrade: adds v2 rows.
      await (database.delete(database.categories)
            ..where((row) => row.id.equals('food_street_food')))
          .go();

      await database.seedDefaultCategories(); // next launch.

      expect(await maybeCategory('food_street_food'), isNull);
    });

    test('a user-renamed new category survives re-seeding', () async {
      await database.seedDefaultCategories();
      await (database.update(database.categories)
            ..where((row) => row.id.equals('pets_vet')))
          .write(
        const CategoriesCompanion(
          name: Value('Dog doctor'),
          icon: Value('custom'),
          isSpending: Value(false),
        ),
      );

      await database.seedDefaultCategories();

      final vet = await category('pets_vet');
      expect(vet.name, 'Dog doctor');
      expect(vet.icon, 'custom');
      expect(vet.isSpending, isFalse);
    });

    test('records the applied seed version in model_meta', () async {
      await database.seedDefaultCategories();
      final marker = await (database.select(database.modelMeta)
            ..where((row) => row.key.equals(categorySeedVersionKey)))
          .getSingle();
      expect(marker.value, '2');
    });

    test('legacy rows keep their always-restored behaviour', () async {
      await database.seedDefaultCategories();
      await (database.delete(database.categories)
            ..where((row) => row.id.equals('other_donations')))
          .go();
      await database.seedDefaultCategories();
      expect(await maybeCategory('other_donations'), isNotNull);
    });

    test('never inserts a row whose parent is missing', () async {
      const json = '''
[
  {"id":"p","name":"P","parent_id":null,"icon":"category","is_spending":true,
   "sort_order":1,"is_user_created":false},
  {"id":"c","name":"C","parent_id":"p","icon":"category","is_spending":true,
   "sort_order":2,"is_user_created":false},
  {"id":"orphan","name":"O","parent_id":"gone","icon":"category",
   "is_spending":true,"sort_order":3,"is_user_created":false,"since":2}
]''';
      await database.seedDefaultCategories(bundle: _StringBundle(json));
      expect(await maybeCategory('p'), isNotNull);
      expect(await maybeCategory('c'), isNotNull);
      expect(await maybeCategory('orphan'), isNull);
    });
  });
}
