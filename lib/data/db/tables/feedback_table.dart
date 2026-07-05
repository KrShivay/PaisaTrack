import 'package:drift/drift.dart';

import 'transactions_table.dart';

/// User corrections captured to improve rules and future parser decisions.
class Feedback extends Table {
  TextColumn get id => text()();
  TextColumn get txnId => text().references(Transactions, #id)();
  TextColumn get field => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  TextColumn get context => text()();
  RealColumn get modelConfidenceAtTime => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
