import 'package:drift/drift.dart';

/// Supporting SMS evidence linked to a transaction (ADR 0032).
///
/// A transaction's primary source stays `transactions.sms_id`. This table
/// records additional messages about the same money movement — a dividend
/// advice, an RD instalment notice, a pre-debit EMI notice or a UPI collect
/// request — so the detail screen can show every message for one
/// transaction. Rows store no message content and, like `sms_dispositions`,
/// have no foreign keys; a linked `raw_sms` row is retained as provenance.
@TableIndex(
  name: 'idx_sms_transaction_links_transaction_id',
  columns: {#transactionId},
)
class SmsTransactionLinks extends Table {
  TextColumn get smsId => text()();
  TextColumn get transactionId => text()();

  /// `dividend` | `rd_instalment` | `emi_notice` | `collect_request` |
  /// `related`.
  TextColumn get kind => text()();

  /// Deterministic matching rule that produced the link.
  TextColumn get basis => text()();
  RealColumn get confidence => real().withDefault(const Constant(1.0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {smsId, transactionId};
}
