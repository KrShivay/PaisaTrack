import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';

/// Reads spending categories for pickers and (later, T-041) the category
/// manager.
class CategoryRepository {
  const CategoryRepository(this._database);

  final AppDatabase _database;

  /// Watches all categories in seed sort order (stable for pickers).
  Stream<List<Category>> watchAll() {
    final query = _database.select(_database.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    return query.watch();
  }

  Future<String> addUserCategory({
    required String name,
    String icon = 'category',
    bool isSpending = true,
    String? parentId,
    DateTime Function() clock = DateTime.now,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    final maxSort = await (_database.selectOnly(_database.categories)
          ..addColumns([_database.categories.sortOrder.max()]))
        .map((row) => row.read(_database.categories.sortOrder.max()) ?? 0)
        .getSingle();
    final id =
        'user_${_slug(trimmed)}_${clock().toUtc().microsecondsSinceEpoch}';
    await _database.into(_database.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            parentId: Value(parentId),
            icon: icon,
            isSpending: isSpending,
            sortOrder: maxSort + 1,
            isUserCreated: true,
          ),
        );
    return id;
  }

  Future<void> renameCategory({
    required String categoryId,
    required String name,
    String? icon,
    bool? isSpending,
    String? parentId,
    bool updateParent = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    await (_database.update(_database.categories)
          ..where((row) => row.id.equals(categoryId)))
        .write(
      CategoriesCompanion(
        name: Value(trimmed),
        icon: icon == null ? const Value.absent() : Value(icon),
        isSpending:
            isSpending == null ? const Value.absent() : Value(isSpending),
        parentId: updateParent ? Value(parentId) : const Value.absent(),
      ),
    );
  }

  Future<void> mergeCategory({
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    if (sourceCategoryId == targetCategoryId) {
      throw ArgumentError.value(sourceCategoryId, 'sourceCategoryId');
    }

    await _database.transaction(() async {
      await (_database.update(_database.transactions)
            ..where((row) => row.categoryId.equals(sourceCategoryId)))
          .write(TransactionsCompanion(categoryId: Value(targetCategoryId)));
      await (_database.update(_database.rules)
            ..where((row) => row.setCategoryId.equals(sourceCategoryId)))
          .write(RulesCompanion(setCategoryId: Value(targetCategoryId)));
      await (_database.update(_database.categories)
            ..where((row) => row.parentId.equals(sourceCategoryId)))
          .write(CategoriesCompanion(parentId: Value(targetCategoryId)));
      await (_database.delete(_database.categories)
            ..where((row) => row.id.equals(sourceCategoryId)))
          .go();
    });
  }

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'category' : slug;
  }
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final categoryRepositoryProvider =
    Provider.family<CategoryRepository, AppDatabase>(
  (ref, database) => CategoryRepository(database),
);
