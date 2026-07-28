import 'package:drift/drift.dart';

/// Key-value feature flags and behavioral thresholds.
class FeatureFlags extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
