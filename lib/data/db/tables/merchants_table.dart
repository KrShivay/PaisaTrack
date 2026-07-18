import 'package:drift/drift.dart';

/// Canonical merchant entities enriched from parsed transaction text.
class Merchants extends Table {
  TextColumn get id => text()();
  TextColumn get canonicalName => text()();
  // User-authored presentation stays separate from resolver evidence.
  TextColumn get userLabel => text().nullable()();
  TextColumn get categoryHint => text().nullable()();
  BlobColumn get embedding => blob().nullable()();
  IntColumn get txnCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
