import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/normalized_transaction_record.dart';
import '../transactions/transactions_providers.dart';

/// Current-month debit/credit totals across non-deleted transactions.
class MonthDirectionTotals {
  const MonthDirectionTotals({
    required this.debitTotal,
    required this.creditTotal,
  });

  final double debitTotal;
  final double creditTotal;
}

/// Derives current-month totals by direction from the already-loaded
/// transaction list, matching the flutter-conventions in-memory-sum pattern
/// (see monthSpendProvider example) rather than a second DB query.
final monthDirectionTotalsProvider = Provider<MonthDirectionTotals>((ref) {
  final transactions = ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  var debitTotal = 0.0;
  var creditTotal = 0.0;

  for (final txn in transactions) {
    final local = txn.ts.toLocal();
    if (local.year != now.year || local.month != now.month) continue;
    switch (txn.direction) {
      case TransactionDirection.debit:
        debitTotal += txn.amount;
      case TransactionDirection.credit:
        creditTotal += txn.amount;
    }
  }

  return MonthDirectionTotals(debitTotal: debitTotal, creditTotal: creditTotal);
});
