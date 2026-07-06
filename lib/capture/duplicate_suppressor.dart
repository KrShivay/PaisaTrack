import '../core/constants.dart';
import '../data/db/database.dart';
import '../data/dedup/duplicate_match_rule.dart';
import '../data/models/normalized_transaction_record.dart';

/// Detects when a newly parsed transaction is a cross-source echo of an
/// already-stored one — e.g. a bank debit alert and a wallet/UPI app's own
/// notification for the same payment (T-025).
///
/// Same-SMS idempotency (re-ingesting one message) is already handled by the
/// deterministic `txn_<smsId>` primary key in `SmsIngestor`; this only covers
/// two *different* SMS describing the same real-world transaction.
///
/// Outcomes write a `duplicate_of_txn_id` link, never `is_deleted` (ADR
/// 0003) — `is_deleted` is reserved for user-initiated soft delete.
class DuplicateSuppressor {
  const DuplicateSuppressor({
    this.window = const Duration(
      minutes: AppConstants.duplicatePairWindowMinutes,
    ),
    this.amountTolerance = 0.005,
  });

  /// Max gap between the two SMS timestamps to still consider them paired.
  final Duration window;

  /// Absolute rupee tolerance when comparing amounts (guards float rounding).
  final double amountTolerance;

  /// True when [candidate] and [existing] look like two notifications for
  /// the same payment: same direction, matching amount, timestamps within
  /// the pairing window, and a matching counterparty (UPI ref id, VPA, or
  /// merchant text). Rows already suppressed as someone else's echo, or
  /// user-deleted, are never a match target.
  bool isDuplicate(
    NormalizedTransactionRecord candidate,
    Transaction existing,
  ) {
    if (existing.isDeleted || existing.duplicateOfTxnId != null) return false;

    return DuplicateMatchRule(
      window: window,
      amountTolerance: amountTolerance,
    ).matches(
      direction: candidate.direction.wireName,
      amount: candidate.amount,
      ts: candidate.ts,
      refId: candidate.refId,
      counterpartyKey: DuplicateMatchRule.counterpartyKeyOf(
        candidate.counterpartyVpa,
        candidate.merchantRaw,
      ),
      existing: existing,
    );
  }
}
