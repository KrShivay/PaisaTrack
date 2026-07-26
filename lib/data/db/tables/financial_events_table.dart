import 'package:drift/drift.dart';

/// Financial events table tracking logical financial events spanning multiple SMS.
class FinancialEvents extends Table {
  TextColumn get id => text()();
  TextColumn get eventKey => text().unique()();
  TextColumn get keyBasis => text()();
  TextColumn get kind => text()();
  IntColumn get netAmountPaise => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  IntColumn get openedAt => integer()();
  IntColumn get closedAt => integer().nullable()();
  TextColumn get state => text().withDefault(const Constant('open'))();
  RealColumn get confidence => real().withDefault(const Constant(1.0))();

  @override
  Set<Column> get primaryKey => {id};
}
