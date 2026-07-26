import 'package:drift/drift.dart';

/// Counterparty identity registry for structured resolution across VPAs, merchants, and P2P payees.
@DataClassName('Counterparty')
class Counterparties extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'person' | 'merchant' | 'institution' | 'self' | 'unknown'
  TextColumn get identityKey => text().unique()();
  TextColumn get displayName => text().nullable()();
  TextColumn get inferredName => text().nullable()();
  TextColumn get pspFamily => text().nullable()();
  TextColumn get merchantId => text().nullable()();
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();
  IntColumn get txnCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
