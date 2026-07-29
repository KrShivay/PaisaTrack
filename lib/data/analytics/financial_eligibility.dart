import '../db/database.dart';

/// The single settled-spending rule used by dashboard and intelligence.
///
/// The SQL fragments deliberately name the aliases used by grouped queries;
/// callers must join categories as `c` when applying [spendingDebitSql].
abstract final class FinancialEligibility {
  static const baseSql = '''
t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL
  AND t.lifecycle_state = 'settled'\n''';

  static const spendingDebitSql = '''
$baseSql  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1\n''';

  static bool includesSpendingDebit(
    Transaction transaction, {
    required bool categoryIsSpending,
  }) =>
      !transaction.isDeleted &&
      transaction.duplicateOfTxnId == null &&
      !transaction.isAnalyticsExcluded &&
      transaction.ownedTransferId == null &&
      transaction.lifecycleState == 'settled' &&
      transaction.direction == 'debit' &&
      categoryIsSpending;
}
