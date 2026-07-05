import 'package:drift/drift.dart';

import 'categories_table.dart';
import 'merchants_table.dart';
import 'raw_sms_table.dart';

/// Normalized financial transactions shown to the user.
///
/// This table stores parsed/enriched transaction fields and links back to raw
/// SMS only while the raw SMS retention window is active.
@TableIndex(name: 'idx_transactions_ts', columns: {#ts})
@TableIndex(name: 'idx_transactions_merchant_id', columns: {#merchantId})
@TableIndex(name: 'idx_transactions_category_id', columns: {#categoryId})
@TableIndex(name: 'idx_transactions_ref_id', columns: {#refId})
@TableIndex(name: 'idx_transactions_status', columns: {#status})
class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get ts => integer()();
  RealColumn get amount => real()();
  TextColumn get direction => text()();
  TextColumn get channel => text()();
  TextColumn get accountHint => text().nullable()();
  TextColumn get merchantRaw => text().nullable()();
  TextColumn get merchantId => text().nullable().references(Merchants, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get description => text().nullable()();
  RealColumn get balanceAfter => real().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get parseSource => text()();
  TextColumn get smsId => text().nullable().references(RawSms, #id)();
  TextColumn get confidenceJson => text()();
  TextColumn get status => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
