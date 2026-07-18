import 'package:drift/drift.dart';

/// A user-owned account, card, wallet, or other source inferred from evidence.
@TableIndex(
  name: 'idx_payment_sources_identity',
  columns: {#kind, #maskedIdentifier},
  unique: true,
)
class PaymentSources extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get maskedIdentifier => text()();
  TextColumn get nickname => text().nullable()();
  TextColumn get institution => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get includeInAnalytics =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isOwned => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
