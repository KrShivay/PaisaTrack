import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('loads bundled category seeds idempotently', () async {
    await database.seedDefaultCategories();

    final seeded = await database.select(database.categories).get();
    expect(seeded, hasLength(87));
    expect(
      seeded.map((category) => category.id),
      containsAll(const [
        'food_dining',
        'cash_withdrawal',
        'food_tea_cigarette',
        'subscriptions_claude',
        'subscriptions_codex',
      ]),
    );
    expect(
      seeded
          .singleWhere((category) => category.id == 'subscriptions_claude')
          .parentId,
      'subscriptions',
    );

    await (database.update(database.categories)
          ..where((category) => category.id.equals('food_dining')))
        .write(
      const CategoriesCompanion(
        name: Value('Food I renamed'),
        icon: Value('custom_food'),
      ),
    );

    await database.seedDefaultCategories();

    final reseeded = await database.select(database.categories).get();
    expect(reseeded, hasLength(87));

    final food = await (database.select(database.categories)
          ..where((category) => category.id.equals('food_dining')))
        .getSingle();
    expect(food.name, 'Food I renamed');
    expect(food.icon, 'custom_food');
  });
}
