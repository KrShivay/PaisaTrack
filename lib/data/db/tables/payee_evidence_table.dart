import 'package:drift/drift.dart';

import 'transactions_table.dart';

/// Rebuildable normalized evidence used by SQL payee aggregation.
@TableIndex(
  name: 'idx_payee_evidence_transaction_id',
  columns: {#transactionId},
)
@TableIndex(
  name: 'idx_payee_evidence_normalized_key',
  columns: {#normalizedKey},
)
class PayeeEvidence extends Table {
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get evidenceType => text()();
  TextColumn get normalizedKey => text()();
  TextColumn get displayValue => text()();

  @override
  Set<Column> get primaryKey => {transactionId, evidenceType};
}
