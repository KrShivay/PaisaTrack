import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/transactions_providers.dart';

class MonthDirectionTotals {
  const MonthDirectionTotals({
    required this.debitTotal,
    required this.creditTotal,
  });

  final double debitTotal;
  final double creditTotal;
}

bool _isCurrentMonth(DateTime ts, DateTime now) {
  final local = ts.toLocal();
  return local.year == now.year && local.month == now.month;
}

bool _isPreviousMonth(DateTime ts, DateTime now) {
  final previous = DateTime(now.year, now.month - 1);
  final local = ts.toLocal();
  return local.year == previous.year && local.month == previous.month;
}

bool _countsAsSpending(TransactionListItem txn) =>
    txn.direction == TransactionDirection.debit && txn.categoryIsSpending;

final monthDirectionTotalsProvider = Provider<MonthDirectionTotals>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  var debitTotal = 0.0;
  var creditTotal = 0.0;

  for (final txn in transactions) {
    if (!_isCurrentMonth(txn.ts, now)) continue;
    switch (txn.direction) {
      case TransactionDirection.debit:
        if (txn.categoryIsSpending) debitTotal += txn.amount;
      case TransactionDirection.credit:
        creditTotal += txn.amount;
    }
  }

  return MonthDirectionTotals(debitTotal: debitTotal, creditTotal: creditTotal);
});

final monthNetProvider = Provider<double>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  return totals.creditTotal - totals.debitTotal;
});

final dailyAverageSpendProvider = Provider<double>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  final daysElapsed = DateTime.now().day;
  if (daysElapsed <= 0) return 0;
  return totals.debitTotal / daysElapsed;
});

final projectedMonthEndSpendProvider = Provider<double>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  final now = DateTime.now();
  final daysElapsed = now.day;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  if (daysElapsed <= 0) return totals.debitTotal;
  return totals.debitTotal / daysElapsed * daysInMonth;
});

class MonthOverMonthSpend {
  const MonthOverMonthSpend({
    required this.current,
    required this.previous,
    required this.pctChange,
  });

  final double current;
  final double previous;
  final double? pctChange;
}

final monthOverMonthSpendProvider = Provider<MonthOverMonthSpend>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  var current = 0.0;
  var previous = 0.0;
  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (_isCurrentMonth(txn.ts, now)) {
      current += txn.amount;
    } else if (_isPreviousMonth(txn.ts, now)) {
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
  final String? icon;
  final double total;
  final double share;
}

const _maxCategorySlices = 5;

final categoryBreakdownProvider = Provider<List<CategorySlice>>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  final totals = <String?, double>{};
  final names = <String?, String>{};
  final icons = <String?, String?>{};
  var grandTotal = 0.0;

  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (!_isCurrentMonth(txn.ts, now)) continue;

    final key = txn.categoryId;
    totals[key] = (totals[key] ?? 0) + txn.amount;
    names[key] = txn.categoryName ?? 'Uncategorised';
    icons[key] = txn.categoryIcon;
    grandTotal += txn.amount;
  }

  if (grandTotal <= 0) return const [];

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

const _maxMerchants = 5;

final topMerchantsProvider = Provider<List<MerchantStat>>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  final totals = <String, double>{};
  final counts = <String, int>{};

  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (!_isCurrentMonth(txn.ts, now)) continue;

    final name = txn.displayName;
    totals[name] = (totals[name] ?? 0) + txn.amount;
    counts[name] = (counts[name] ?? 0) + 1;
  }

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

class MonthPoint {
  const MonthPoint({required this.month, required this.spend});

  final DateTime month;
  final double spend;
}

const _trendMonths = 6;

final sixMonthTrendProvider = Provider<List<MonthPoint>>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final now = DateTime.now();

  final buckets = <String, double>{};
  final order = <String, DateTime>{};
  for (var i = _trendMonths - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    final key = '${month.year}-${month.month}';
    buckets[key] = 0;
    order[key] = month;
  }

  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    final local = txn.ts.toLocal();
    final key = '${local.year}-${local.month}';
    if (!buckets.containsKey(key)) continue;
    buckets[key] = (buckets[key] ?? 0) + txn.amount;
  }

  final keys = order.keys.toList()
    ..sort((a, b) => order[a]!.compareTo(order[b]!));
  return [
    for (final key in keys)
      MonthPoint(month: order[key]!, spend: buckets[key]!),
  ];
});

class ReviewAttention {
  const ReviewAttention({
    required this.count,
    required this.amount,
    required this.highestImpactLabel,
  });

  final int count;
  final double amount;
  final String highestImpactLabel;
}

final reviewAttentionProvider = Provider<ReviewAttention?>((ref) {
  final reviewItems = ref.watch(reviewQueueProvider).valueOrNull ?? const [];
  if (reviewItems.isEmpty) return null;

  var amount = 0.0;
  TransactionReviewItem? highest;
  for (final item in reviewItems) {
    amount += item.amount;
    if (highest == null || item.amount > highest.amount) highest = item;
  }

  return ReviewAttention(
    count: reviewItems.length,
    amount: amount,
    highestImpactLabel: highest?.displayName ?? 'Unknown transaction',
  );
});

final recentTransactionsProvider = Provider<List<TransactionListItem>>((ref) {
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  return transactions.take(6).toList(growable: false);
});
