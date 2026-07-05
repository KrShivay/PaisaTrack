import 'package:drift/drift.dart';

import 'merchants_table.dart';

/// Mapping from raw merchant strings to canonical merchant records.
class MerchantAliases extends Table {
  TextColumn get alias => text()();
  TextColumn get merchantId => text().references(Merchants, #id)();
  TextColumn get source => text()();
  RealColumn get confidence => real()();

  @override
  Set<Column> get primaryKey => {alias};
}
