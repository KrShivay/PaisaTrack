import 'package:drift/drift.dart';

/// A deterministic insight precomputed for a reporting period.
@TableIndex(name: 'idx_insights_period', columns: {#period})
class Insights extends Table {
  TextColumn get id => text()();
  TextColumn get period => text()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
