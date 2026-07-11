import 'package:drift/drift.dart';

/// Versioned model state and policy settings, stored as key-value metadata.
class ModelMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
