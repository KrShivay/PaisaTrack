import 'package:drift/drift.dart';

import 'categories_table.dart';
import 'merchants_table.dart';
import 'payment_sources_table.dart';
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
@TableIndex(
  name: 'idx_transactions_payment_source_id',
  columns: {#paymentSourceId},
)
@TableIndex(
  name: 'idx_transactions_owned_transfer_id',
  columns: {#ownedTransferId},
)
@TableIndex(
  name: 'idx_transactions_duplicate_of_txn_id',
  columns: {#duplicateOfTxnId},
)
class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get ts => integer()();
  RealColumn get amount => real()();
  TextColumn get direction => text()();
  TextColumn get channel => text()();
  TextColumn get accountHint => text().nullable()();
  TextColumn get paymentSourceId =>
      text().nullable().references(PaymentSources, #id)();
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
  // v1 meaning was overloaded (user delete + system dedup suppression); v2
  // (ADR 0003) narrows this back to user-initiated soft delete only.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  // Independent counterparty signal for P2P rule matching (ADR 0003); no
  // longer folded into merchantRaw at write time.
  TextColumn get counterpartyVpa => text().nullable()();
  // Non-null => this row is a cross-source echo of the referenced row
  // (ADR 0003). Replaces the v1 `isDeleted` overload for dedup suppression.
  TextColumn get duplicateOfTxnId =>
      text().nullable().references(Transactions, #id)();
  // Shared id on a conservative debit/credit pair between owned sources.
  TextColumn get ownedTransferId => text().nullable()();
  // Materialized source policy keeps all analytics engines consistent.
  BoolColumn get isAnalyticsExcluded =>
      boolean().withDefault(const Constant(false))();
  TextColumn get evidenceJson => text().nullable()();
  // v9 columns for lifecycle state split (T-132a).
  TextColumn get lifecycleState =>
      text().withDefault(const Constant('settled'))();
  TextColumn get lifecycleReason => text().nullable()();
  TextColumn get messageKind => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
