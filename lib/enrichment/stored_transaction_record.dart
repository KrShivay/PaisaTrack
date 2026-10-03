import '../data/db/database.dart' show Transaction;
import '../data/models/normalized_transaction_record.dart';

/// Rebuilds the categorizer input from a stored transaction (read path only),
/// so suggestions can be recomputed after the user corrects a field.
NormalizedTransactionRecord normalizedRecordOf(Transaction txn) {
  return NormalizedTransactionRecord(
    amount: txn.amount,
    direction: TransactionDirection.values.byName(txn.direction),
    channel: TransactionChannel.values.byName(txn.channel),
    merchantRaw: txn.merchantRaw,
    counterpartyVpa: txn.counterpartyVpa,
    accountHint: txn.accountHint,
    balanceAfter: txn.balanceAfter,
    refId: txn.refId,
    ts: DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true),
    parseSource: ParseSource.values.firstWhere(
      (source) => source.wireName == txn.parseSource,
      orElse: () => ParseSource.generic,
    ),
    parseConfidence: 1,
  );
}
