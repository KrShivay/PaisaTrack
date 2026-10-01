import 'package:drift/drift.dart';

import '../db/database.dart';

/// The single settled-spending rule used by dashboard and intelligence.
///
/// The SQL fragments deliberately name the aliases used by grouped queries;
/// callers must join categories as `c` when applying [spendingDebitSql].
abstract final class FinancialEligibility {
  /// Common settled row validity before source-policy flags are applied.
  static Expression<bool> settledTransaction($TransactionsTable t) =>
      t.isDeleted.equals(false) &
      t.isNotTransaction.equals(false) &
      t.duplicateOfTxnId.isNull() &
      t.lifecycleState.equals('settled');

  /// Drift form of [baseSql], shared by structured queries.
  static Expression<bool> base($TransactionsTable t) =>
      settledTransaction(t) &
      t.isAnalyticsExcluded.equals(false) &
      t.ownedTransferId.isNull();

  /// Drift form of [spendingDebitSql]. A missing category and a null category
  /// both default to spending, matching SQL's `COALESCE(c.is_spending, 1)`.
  static Expression<bool> spendingDebit(
    $TransactionsTable t,
    $CategoriesTable categories,
  ) {
    final nonSpendingCategoryIds = categories.attachedDatabase.selectOnly(
      categories,
    )
      ..addColumns([categories.id])
      ..where(categories.isSpending.equals(false));
    return base(t) &
        t.direction.equals('debit') &
        (t.categoryId.isNull() |
            t.categoryId.isNotInQuery(nonSpendingCategoryIds));
  }

  static const settledSql = '''
t.is_deleted = 0
  AND t.is_not_transaction = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.lifecycle_state = 'settled'\n''';

  static const baseSql = '''
$settledSql  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL\n''';

  static const spendingDebitSql = '''
$baseSql  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1\n''';

  /// Settled spending before source-policy exclusions, for explaining rows
  /// removed specifically by those flags (not for headline totals).
  static const spendingDebitBeforeSourcePolicySql = '''
$settledSql  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1\n''';

  static bool includesSpendingDebit(
    Transaction transaction, {
    bool? categoryIsSpending,
  }) =>
      !transaction.isDeleted &&
      !transaction.isNotTransaction &&
      transaction.duplicateOfTxnId == null &&
      !transaction.isAnalyticsExcluded &&
      transaction.ownedTransferId == null &&
      transaction.lifecycleState == 'settled' &&
      transaction.direction == 'debit' &&
      (categoryIsSpending ?? true);
}
