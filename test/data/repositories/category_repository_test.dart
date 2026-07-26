import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/category_repository.dart';

void main() {
  // seedDefaultCategories() loads a bundled asset, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late CategoryRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = CategoryRepository(database);
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
  });

  test('add, rename, and merge retro-apply transactions and rules', () async {
    final sourceId = await repository.addUserCategory(
      name: 'Coffee Runs',
      parentId: 'food_dining',
      clock: () => DateTime.utc(2026, 7, 8),
    );
    await repository.renameCategory(
      categoryId: sourceId,
      name: 'Coffee',
      icon: 'local_cafe',
      isSpending: false,
    );
    final renamed = await (database.select(database.categories)
          ..where((row) => row.id.equals(sourceId)))
        .getSingle();
    expect(renamed.icon, 'local_cafe');
    expect(renamed.isSpending, isFalse);
    expect(renamed.parentId, 'food_dining');

    final now = DateTime.utc(2026, 7, 8, 9);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1',
            ts: now.millisecondsSinceEpoch,
            amount: 200,
            direction: 'debit',
            channel: 'upi',
            categoryId: Value(sourceId),
            parseSource: 'manual',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.rules).insert(
          RulesCompanion.insert(
            id: 'rule_1',
            matchType: 'merchant',
            matchValue: 'cafe',
            setCategoryId: Value(sourceId),
            createdAt: now,
          ),
        );

    await repository.mergeCategory(
      sourceCategoryId: sourceId,
      targetCategoryId: 'food_dining',
    );

    final txn = await database.select(database.transactions).getSingle();
    final rule = await database.select(database.rules).getSingle();
    final source = await (database.select(database.categories)
          ..where((row) => row.id.equals(sourceId)))
        .get();

    expect(txn.categoryId, 'food_dining');
    expect(rule.setCategoryId, 'food_dining');
    expect(source, isEmpty);
  });
}
