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

/// Net cash flow this month (received minus spent). Positive means the user
/// took in more than they spent.
final monthNetProvider = Provider<double>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  return totals.creditTotal - totals.debitTotal;
});

/// Average daily spend so far this month: total debit divided by the number of
/// days elapsed (1..today), so early in the month a single big day does not
/// read as the whole-month rate.
final dailyAverageSpendProvider = Provider<double>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  final daysElapsed = DateTime.now().day;
  if (daysElapsed <= 0) return 0;
  return totals.debitTotal / daysElapsed;
});

/// Month-over-month spend comparison: this month's debit total vs. last
/// month's, with a signed percent change (null when last month had no spend).
class MonthOverMonthSpend {
  const MonthOverMonthSpend({
    required this.current,
    required this.previous,
    required this.pctChange,
  });

  final double current;
  final double previous;

  /// Signed fractional change (0.2 == +20%); null when [previous] is zero.
  final double? pctChange;
}

final monthOverMonthSpendProvider = Provider<MonthOverMonthSpend>((ref) {
  final transactions = ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  final prev = DateTime(now.year, now.month - 1);

  var current = 0.0;
  var previous = 0.0;
  for (final txn in transactions) {
    if (txn.direction != TransactionDirection.debit) continue;
    final local = txn.ts.toLocal();
    if (local.year == now.year && local.month == now.month) {
      current += txn.amount;
    } else if (local.year == prev.year && local.month == prev.month) {
      previous += txn.amount;
    }
  }

  final pct = previous > 0 ? (current - previous) / previous : null;
  return MonthOverMonthSpend(
    current: current,
    previous: previous,
    pctChange: pct,
  );
});

/// One category's share of this month's spending.
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.total,
    required this.share,
  });

  final String? categoryId;
  final String name;

  /// Material icon identifier from the transaction (may be null / unknown).
  final String? icon;
  final double total;

  /// Fraction of total month spend (0..1).
  final double share;
}

/// Top spending categories for the current month (debit only), sorted
/// descending, capped to [_maxCategorySlices] with the remainder bucketed into
/// a trailing "Other" slice. Uncategorised spend groups under "Uncategorised".
const _maxCategorySlices = 5;

final categoryBreakdownProvider = Provider<List<CategorySlice>>((ref) {
  final transactions = ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  final totals = <String?, double>{};
  final names = <String?, String>{};
  final icons = <String?, String?>{};
  var grandTotal = 0.0;

  for (final txn in transactions) {
    if (txn.direction != TransactionDirection.debit) continue;
    final local = txn.ts.toLocal();
    if (local.year != now.year || local.month != now.month) continue;

    final key = txn.categoryId;
    totals[key] = (totals[key] ?? 0) + txn.amount;
    names[key] = txn.categoryName ?? 'Uncategorised';
    icons[key] = txn.categoryIcon;
    grandTotal += txn.amount;
  }

  if (grandTotal <= 0) return const [];

  // Sort by spend descending; break ties by category name (A→Z) so the order
  // is deterministic regardless of transaction insertion order.
  final entries = totals.entries.toList()
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      if (byValue != 0) return byValue;
      return (names[a.key] ?? '').compareTo(names[b.key] ?? '');
    });

  final slices = <CategorySlice>[];
  final top = entries.take(_maxCategorySlices);
  for (final entry in top) {
    slices.add(
      CategorySlice(
        categoryId: entry.key,
        name: names[entry.key] ?? 'Uncategorised',
        icon: icons[entry.key],
        total: entry.value,
        share: entry.value / grandTotal,
      ),
    );
  }

  if (entries.length > _maxCategorySlices) {
    final otherTotal = entries
        .skip(_maxCategorySlices)
        .fold<double>(0, (sum, e) => sum + e.value);
    slices.add(
      CategorySlice(
        categoryId: null,
        name: 'Other',
        icon: null,
        total: otherTotal,
        share: otherTotal / grandTotal,
      ),
    );
  }

  return slices;
});

/// A merchant's spend and frequency this month.
class MerchantStat {
  const MerchantStat({
    required this.name,
    required this.count,
    required this.total,
  });

  final String name;
  final int count;
  final double total;
}

/// Top merchants by total debit this month, most spent first.
const _maxMerchants = 5;

final topMerchantsProvider = Provider<List<MerchantStat>>((ref) {
  final transactions = ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  final totals = <String, double>{};
  final counts = <String, int>{};

  for (final txn in transactions) {
    if (txn.direction != TransactionDirection.debit) continue;
    final local = txn.ts.toLocal();
    if (local.year != now.year || local.month != now.month) continue;

    final name = txn.displayName;
    totals[name] = (totals[name] ?? 0) + txn.amount;
    counts[name] = (counts[name] ?? 0) + 1;
  }

  // Sort by spend descending; break ties by merchant name (A→Z) so equal-spend
  // merchants keep a deterministic order regardless of insertion order.
  final entries = totals.entries.toList()
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      if (byValue != 0) return byValue;
      return a.key.compareTo(b.key);
    });

  return [
    for (final e in entries.take(_maxMerchants))
      MerchantStat(
        name: e.key,
        count: counts[e.key] ?? 0,
        total: e.value,
      ),
  ];
});

/// One month's spend total for the trend sparkline.
class MonthPoint {
  const MonthPoint({required this.month, required this.spend});

  /// First day of the month this point represents.
  final DateTime month;
  final double spend;
}

/// Spend totals for the trailing six months (oldest first, including the
/// current month) for an at-a-glance direction sparkline.
const _trendMonths = 6;

final sixMonthTrendProvider = Provider<List<MonthPoint>>((ref) {
  final transactions = ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  // Seed buckets for each of the last six months so gaps render as zero.
  final buckets = <String, double>{};
  final order = <String, DateTime>{};
  for (var i = _trendMonths - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    final key = '${m.year}-${m.month}';
    buckets[key] = 0;
    order[key] = m;
  }

  for (final txn in transactions) {
    if (txn.direction != TransactionDirection.debit) continue;
    final local = txn.ts.toLocal();
    final key = '${local.year}-${local.month}';
    if (!buckets.containsKey(key)) continue;
    buckets[key] = (buckets[key] ?? 0) + txn.amount;
  }

  final keys = order.keys.toList()
    ..sort((a, b) => order[a]!.compareTo(order[b]!));
  return [
    for (final key in keys) MonthPoint(month: order[key]!, spend: buckets[key]!),
  ];
});
