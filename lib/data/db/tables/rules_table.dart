import 'package:drift/drift.dart';

import 'categories_table.dart';
import 'transactions_table.dart';

/// User-taught deterministic mappings applied before probabilistic enrichment.
class Rules extends Table {
  TextColumn get id => text()();
  TextColumn get matchType => text()();
  TextColumn get matchValue => text()();
  TextColumn get setCategoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get setDescription => text().nullable()();
  TextColumn get createdFromTxnId =>
      text().nullable().references(Transactions, #id)();
  IntColumn get hitCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
