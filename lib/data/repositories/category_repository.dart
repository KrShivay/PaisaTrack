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
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final categoryRepositoryProvider =
    Provider.family<CategoryRepository, AppDatabase>(
  (ref, database) => CategoryRepository(database),
);
