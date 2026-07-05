import 'package:drift/drift.dart';

/// Hierarchical spending categories used for transaction classification.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  TextColumn get icon => text()();
  BoolColumn get isSpending => boolean()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isUserCreated => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}
