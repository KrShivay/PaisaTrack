import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../recurring/recurring_screen.dart';
import '../transactions/transactions_providers.dart';

class DashboardPeriod {
  const DashboardPeriod({
    required this.start,
    required this.end,
    required this.label,
    required this.isCalendarMonth,
  });

  factory DashboardPeriod.month(DateTime value) {
    final start = DateTime(value.year, value.month);
    return DashboardPeriod(
      start: start,
      end: DateTime(value.year, value.month + 1),
      label: '${_monthNames[value.month - 1]} ${value.year}',
      isCalendarMonth: true,
    );
  }

  factory DashboardPeriod.lastDays(int days, {DateTime? now}) {
    assert(days > 0);
    final today = _localDay(now ?? DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    return DashboardPeriod(
      start: start,
      end: today.add(const Duration(days: 1)),
      label: days == 1 ? _dateLabel(today) : 'Last $days days',
      isCalendarMonth: false,
    );
  }

  factory DashboardPeriod.range(DateTime start, DateTime inclusiveEnd) {
    final localStart = _localDay(start);
    final localEnd = _localDay(inclusiveEnd);
    assert(!localEnd.isBefore(localStart));
    return DashboardPeriod(
      start: localStart,
      end: localEnd.add(const Duration(days: 1)),
      label: _rangeLabel(localStart, localEnd),
      isCalendarMonth: false,
    );
  }

  final DateTime start;
  final DateTime end;
  final String label;
  final bool isCalendarMonth;

  bool contains(DateTime timestamp) {
    final local = timestamp.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  bool isCurrentMonth([DateTime? value]) {
    if (!isCalendarMonth) return false;
    final now = value ?? DateTime.now();
    return start.year == now.year && start.month == now.month;
  }

  int elapsedDays([DateTime? value]) {
    final tomorrow =
        _localDay(value ?? DateTime.now()).add(const Duration(days: 1));
    final effectiveEnd = end.isBefore(tomorrow) ? end : tomorrow;
    if (!start.isBefore(effectiveEnd)) return 0;
    return effectiveEnd.difference(start).inDays;
  }

  DashboardPeriod get previous {
    if (isCalendarMonth) {
      return DashboardPeriod.month(DateTime(start.year, start.month - 1));
    }
    final duration = end.difference(start);
    final previousEnd = start;
    final previousStart = previousEnd.subtract(duration);
    return DashboardPeriod(
      start: previousStart,
      end: previousEnd,
      label: _rangeLabel(
        previousStart,
        previousEnd.subtract(const Duration(days: 1)),
      ),
      isCalendarMonth: false,
    );
  }

  String get comparisonLabel =>
      isCalendarMonth ? 'vs previous month' : 'vs previous period';

  DateTime get trendAnchor => end.subtract(const Duration(microseconds: 1));

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateLabel(DateTime value) =>
      '${value.day} ${_monthNames[value.month - 1]} ${value.year}';

  static String _rangeLabel(DateTime start, DateTime end) {
    if (start == end) return _dateLabel(start);
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}–${end.day} ${_monthNames[start.month - 1]} '
          '${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${_shortMonthNames[start.month - 1]}–'
          '${end.day} ${_shortMonthNames[end.month - 1]} ${start.year}';
    }
    return '${_dateLabel(start)}–${_dateLabel(end)}';
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _shortMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

enum DashboardMetricChoice { safeToday, netFlow, burn, runway }

final selectedDashboardMetricProvider = StateProvider<DashboardMetricChoice>(
  (ref) => DashboardMetricChoice.safeToday,
);

final dashboardPeriodProvider = StateProvider<DashboardPeriod>(
  (ref) => DashboardPeriod.month(DateTime.now()),
);

final dashboardAggregateProvider =
    FutureProvider<DashboardAggregateSnapshot>((ref) async {
  ref.watch(transactionListProvider);
  final database = await ref.watch(appDatabaseProvider.future);
  final period = ref.watch(dashboardPeriodProvider);
  final previous = period.previous;
  final anchor = period.trendAnchor;
  final trendStart = DateTime(anchor.year, anchor.month - (_trendMonths - 1));
  final trendEnd = DateTime(anchor.year, anchor.month + 1);
  return DashboardRepository(database).load(
    DashboardQueryWindow(
      start: period.start,
      end: period.end,
      previousStart: previous.start,
      previousEnd: previous.end,
      trendStart: trendStart,
      trendEnd: trendEnd,
    ),
  );
});

final dashboardRecentTransactionsProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  final period = ref.watch(dashboardPeriodProvider);
  return databaseAsync.when(
    data: (database) => ref
        .watch(transactionRepositoryProvider(database))
        .watchTransactions(limit: 6, start: period.start, end: period.end),
    loading: () => const Stream<List<TransactionListItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TransactionListItem>>.error(error, stackTrace),
  );
});

class MonthDirectionTotals {
  const MonthDirectionTotals({
    required this.debitTotal,
    required this.creditTotal,
  });

  final double debitTotal;
  final double creditTotal;
}

bool _countsAsSpending(TransactionListItem txn) =>
    txn.includeInAnalytics &&
    !txn.isOwnedTransfer &&
    txn.direction == TransactionDirection.debit &&
    txn.categoryIsSpending;

final monthDirectionTotalsProvider = Provider<MonthDirectionTotals>((ref) {
  final aggregate = ref.watch(dashboardAggregateProvider).valueOrNull;
  if (aggregate != null) {
    return MonthDirectionTotals(
      debitTotal: aggregate.debitTotal,
      creditTotal: aggregate.creditTotal,
    );
  }
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final period = ref.watch(dashboardPeriodProvider);
  var debitTotal = 0.0;
  var creditTotal = 0.0;

  for (final txn in transactions) {
    if (!period.contains(txn.ts)) continue;
    if (!txn.includeInAnalytics || txn.isOwnedTransfer) continue;
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
  final daysElapsed = ref.watch(dashboardPeriodProvider).elapsedDays();
  if (daysElapsed <= 0) return 0;
  return totals.debitTotal / daysElapsed;
});

final commitmentsTotalProvider = Provider<double>((ref) {
  final upcoming = ref.watch(upcomingRecurringProvider);
  final now = DateTime.now();
  var sum = 0.0;
  for (final series in upcoming) {
    if (series.nextExpectedDate.year == now.year &&
        series.nextExpectedDate.month == now.month) {
      sum += series.expectedAmount;
    }
  }
  return sum;
});

/// Safe today = (budget - spent - remaining commitments) / inclusive days remaining.
final safeTodayValueProvider = Provider<double?>((ref) {
  final budget = ref.watch(monthlyBudgetProvider).valueOrNull;
  if (budget == null) return null;

  final totals = ref.watch(monthDirectionTotalsProvider);
  final commitments = ref.watch(commitmentsTotalProvider);
  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daysRemaining = daysInMonth - now.day + 1;
  if (daysRemaining <= 0) return 0;

  final remainingBudget = budget - totals.debitTotal - commitments;
  return remainingBudget / daysRemaining;
});

/// Runway in days = (budget - spent - commitments) / daily burn.
final runwayValueProvider = Provider<double?>((ref) {
  final budget = ref.watch(monthlyBudgetProvider).valueOrNull;
  if (budget == null) return null;

  final totals = ref.watch(monthDirectionTotalsProvider);
  final commitments = ref.watch(commitmentsTotalProvider);
  final burn = ref.watch(dailyAverageSpendProvider);
  if (burn <= 0) return null;

  final remainingBudget = budget - totals.debitTotal - commitments;
  return remainingBudget / burn;
});

final projectedMonthEndSpendProvider = Provider<double?>((ref) {
  final totals = ref.watch(monthDirectionTotalsProvider);
  final period = ref.watch(dashboardPeriodProvider);
  if (!period.isCurrentMonth()) return null;
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
  final aggregate = ref.watch(dashboardAggregateProvider).valueOrNull;
  if (aggregate != null) {
    final current = aggregate.debitTotal;
    final previous = aggregate.previousSpend;
    return MonthOverMonthSpend(
      current: current,
      previous: previous,
      pctChange: previous > 0 ? (current - previous) / previous : null,
    );
  }
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final period = ref.watch(dashboardPeriodProvider);
  final previousPeriod = period.previous;

  var current = 0.0;
  var previous = 0.0;
  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (period.contains(txn.ts)) {
      current += txn.amount;
    } else if (previousPeriod.contains(txn.ts)) {
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
  final aggregate = ref.watch(dashboardAggregateProvider).valueOrNull;
  if (aggregate != null) {
    final entries = aggregate.categories;
    final grandTotal = entries.fold<double>(0, (sum, row) => sum + row.total);
    if (grandTotal <= 0) return const [];
    final slices = [
      for (final row in entries.take(_maxCategorySlices))
        CategorySlice(
          categoryId: row.categoryId,
          name: row.name,
          icon: row.icon,
          total: row.total,
          share: row.total / grandTotal,
        ),
    ];
    if (entries.length > _maxCategorySlices) {
      final otherTotal = entries
          .skip(_maxCategorySlices)
          .fold<double>(0, (sum, row) => sum + row.total);
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
  }
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final period = ref.watch(dashboardPeriodProvider);

  final totals = <String?, double>{};
  final names = <String?, String>{};
  final icons = <String?, String?>{};
  var grandTotal = 0.0;

  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (!period.contains(txn.ts)) continue;

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
  final aggregate = ref.watch(dashboardAggregateProvider).valueOrNull;
  if (aggregate != null) {
    return [
      for (final row in aggregate.merchants)
        MerchantStat(name: row.name, count: row.count, total: row.total),
    ];
  }
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final period = ref.watch(dashboardPeriodProvider);

  final totals = <String, double>{};
  final counts = <String, int>{};

  for (final txn in transactions) {
    if (!_countsAsSpending(txn)) continue;
    if (!period.contains(txn.ts)) continue;

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
  final aggregate = ref.watch(dashboardAggregateProvider).valueOrNull;
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final anchor = ref.watch(dashboardPeriodProvider).trendAnchor;

  final buckets = <String, double>{};
  final order = <String, DateTime>{};
  for (var i = _trendMonths - 1; i >= 0; i--) {
    final month = DateTime(anchor.year, anchor.month - i);
    final key = '${month.year}-${month.month}';
    buckets[key] = aggregate?.trendByMonth[
            '${month.year}-${month.month.toString().padLeft(2, '0')}'] ??
        0;
    order[key] = month;
  }

  if (aggregate == null) {
    for (final txn in transactions) {
      if (!_countsAsSpending(txn)) continue;
      final local = txn.ts.toLocal();
      final key = '${local.year}-${local.month}';
      if (!buckets.containsKey(key)) continue;
      buckets[key] = (buckets[key] ?? 0) + txn.amount;
    }
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
  final summary = ref.watch(reviewQueueSummaryProvider).valueOrNull;
  if (summary == null || summary.count == 0) return null;

  return ReviewAttention(
    count: summary.count,
    amount: summary.amount,
    highestImpactLabel: summary.highestImpactLabel,
  );
});

final recentTransactionsProvider = Provider<List<TransactionListItem>>((ref) {
  final bounded = ref.watch(dashboardRecentTransactionsProvider).valueOrNull;
  if (bounded != null) return bounded;
  final transactions =
      ref.watch(transactionListProvider).valueOrNull ?? const [];
  final period = ref.watch(dashboardPeriodProvider);
  return transactions
      .where((transaction) => period.contains(transaction.ts))
      .take(6)
      .toList(growable: false);
});

final upcomingRecurringProvider = Provider<List<RecurringSery>>((ref) {
  final series = ref.watch(recurringSeriesProvider).valueOrNull ?? const [];
  final upcoming = series
      .where((item) => item.status != 'inactive')
      .toList(growable: false)
    ..sort((a, b) => a.nextExpectedDate.compareTo(b.nextExpectedDate));
  return upcoming.take(3).toList(growable: false);
});
