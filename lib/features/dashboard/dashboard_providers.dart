import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/financial_calendar.dart';
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
    required this.calendar,
  });

  factory DashboardPeriod.month(
    DateTime value, {
    FinancialCalendar? calendar,
  }) {
    final boundary = calendar ?? FinancialCalendar();
    final local = boundary.localDate(value);
    final period = boundary.monthContaining(value);
    return DashboardPeriod(
      start: period.start,
      end: period.end,
      label: '${_monthNames[local.month - 1]} ${local.year}',
      isCalendarMonth: true,
      calendar: boundary,
    );
  }

  factory DashboardPeriod.lastDays(
    int days, {
    DateTime? now,
    FinancialCalendar? calendar,
  }) {
    assert(days > 0);
    final boundary = calendar ?? FinancialCalendar();
    final today = boundary.localDate(now ?? DateTime.now());
    final day = boundary.dayContaining(now ?? DateTime.now());
    final start = day.start.subtract(Duration(days: days - 1));
    return DashboardPeriod(
      start: start,
      end: day.end,
      label: days == 1 ? _dateLabel(today) : 'Last $days days',
      isCalendarMonth: false,
      calendar: boundary,
    );
  }

  factory DashboardPeriod.range(
    DateTime start,
    DateTime inclusiveEnd, {
    FinancialCalendar? calendar,
  }) {
    final boundary = calendar ?? FinancialCalendar();
    final localStart = boundary.localDate(start);
    final localEnd = boundary.localDate(inclusiveEnd);
    assert(!localEnd.isBefore(localStart));
    final startPeriod = boundary.dayContaining(start);
    final endPeriod = boundary.dayContaining(inclusiveEnd);
    return DashboardPeriod(
      start: startPeriod.start,
      end: endPeriod.end,
      label: _rangeLabel(localStart, localEnd),
      isCalendarMonth: false,
      calendar: boundary,
    );
  }

  final DateTime start;
  final DateTime end;
  final String label;
  final bool isCalendarMonth;
  final FinancialCalendar calendar;

  bool contains(DateTime timestamp) =>
      !timestamp.toUtc().isBefore(start) && timestamp.toUtc().isBefore(end);

  bool isCurrentMonth([DateTime? value]) {
    if (!isCalendarMonth) return false;
    final now = calendar.localDate(value ?? DateTime.now());
    final monthStart = calendar.localDate(start);
    return monthStart.year == now.year && monthStart.month == now.month;
  }

  int elapsedDays([DateTime? value]) {
    final tomorrow = calendar.dayContaining(value ?? DateTime.now()).end;
    final effectiveEnd = end.isBefore(tomorrow) ? end : tomorrow;
    if (!start.isBefore(effectiveEnd)) return 0;
    return effectiveEnd.difference(start).inDays;
  }

  DashboardPeriod get previous {
    if (isCalendarMonth) {
      return DashboardPeriod.month(
        start.subtract(const Duration(days: 1)),
        calendar: calendar,
      );
    }
    final duration = end.difference(start);
    final previousEnd = start;
    final previousStart = previousEnd.subtract(duration);
    return DashboardPeriod(
      start: previousStart,
      end: previousEnd,
      label: _rangeLabel(
        calendar.localDate(previousStart),
        calendar.localDate(
          previousEnd.subtract(const Duration(days: 1)),
        ),
      ),
      isCalendarMonth: false,
      calendar: calendar,
    );
  }

  String get comparisonLabel =>
      isCalendarMonth ? 'vs previous month' : 'vs previous period';

  DateTime get trendAnchor => end.subtract(const Duration(microseconds: 1));

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
      timeZoneOffset: period.calendar.timeZoneOffset,
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

/// Settled debit/credit totals for the active period.
///
/// Sourced only from the SQL aggregate — the sole valid source for full-period
/// totals. Loading and error propagate as [AsyncValue] so the UI keeps those
/// states distinct from real data; it never substitutes the bounded 100-row
/// transaction feed, which would understate any period with more than one page
/// of history (PV-02).
final monthDirectionTotalsProvider =
    Provider<AsyncValue<MonthDirectionTotals>>((ref) {
  return ref.watch(dashboardAggregateProvider).whenData(
        (aggregate) => MonthDirectionTotals(
          debitTotal: aggregate.debitTotal,
          creditTotal: aggregate.creditTotal,
        ),
      );
});

final monthNetProvider = Provider<AsyncValue<double>>((ref) {
  return ref
      .watch(monthDirectionTotalsProvider)
      .whenData((totals) => totals.creditTotal - totals.debitTotal);
});

final dailyAverageSpendProvider = Provider<AsyncValue<double>>((ref) {
  final daysElapsed = ref.watch(dashboardPeriodProvider).elapsedDays();
  return ref.watch(monthDirectionTotalsProvider).whenData(
        (totals) => daysElapsed <= 0 ? 0.0 : totals.debitTotal / daysElapsed,
      );
});

final commitmentsTotalProvider = Provider<double>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  if (!period.isCurrentMonth()) return 0;
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
/// Only meaningful for the current calendar month — returns null otherwise.
final safeTodayValueProvider = Provider<AsyncValue<double?>>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  if (!period.isCurrentMonth()) return const AsyncData(null);

  final budget = ref.watch(monthlyBudgetProvider).valueOrNull;
  if (budget == null) return const AsyncData(null);

  final commitments = ref.watch(commitmentsTotalProvider);
  return ref.watch(monthDirectionTotalsProvider).whenData<double?>((totals) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysRemaining = daysInMonth - now.day + 1;
    if (daysRemaining <= 0) return 0.0;
    return (budget - totals.debitTotal - commitments) / daysRemaining;
  });
});

/// Runway in days = (budget - spent - commitments) / daily burn.
/// Only meaningful for the current calendar month — returns null otherwise.
final runwayValueProvider = Provider<AsyncValue<double?>>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  if (!period.isCurrentMonth()) return const AsyncData(null);

  final budget = ref.watch(monthlyBudgetProvider).valueOrNull;
  if (budget == null) return const AsyncData(null);

  final commitments = ref.watch(commitmentsTotalProvider);
  return ref.watch(monthDirectionTotalsProvider).whenData<double?>((totals) {
    final daysElapsed = period.elapsedDays();
    final burn = daysElapsed <= 0 ? 0.0 : totals.debitTotal / daysElapsed;
    if (burn <= 0) return null;
    return (budget - totals.debitTotal - commitments) / burn;
  });
});

final projectedMonthEndSpendProvider = Provider<AsyncValue<double?>>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  if (!period.isCurrentMonth()) return const AsyncData(null);
  return ref.watch(monthDirectionTotalsProvider).whenData<double?>((totals) {
    final now = DateTime.now();
    final daysElapsed = now.day;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    if (daysElapsed <= 0) return totals.debitTotal;
    return totals.debitTotal / daysElapsed * daysInMonth;
  });
});

/// Spending removed from the headline total by exclusion flags (self-transfers
/// and analytics-excluded sources) in the active period. Drives the dashboard
/// completeness note so excluded money is explained, not silently dropped.
class DashboardExclusions {
  const DashboardExclusions({required this.total, required this.count});

  final double total;
  final int count;
}

final dashboardExclusionsProvider =
    Provider<AsyncValue<DashboardExclusions>>((ref) {
  return ref.watch(dashboardAggregateProvider).whenData(
        (aggregate) => DashboardExclusions(
          total: aggregate.excludedDebitTotal,
          count: aggregate.excludedDebitCount,
        ),
      );
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

final monthOverMonthSpendProvider =
    Provider<AsyncValue<MonthOverMonthSpend>>((ref) {
  return ref.watch(dashboardAggregateProvider).whenData((aggregate) {
    final current = aggregate.debitTotal;
    final previous = aggregate.previousSpend;
    return MonthOverMonthSpend(
      current: current,
      previous: previous,
      pctChange: previous > 0 ? (current - previous) / previous : null,
    );
  });
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

final categoryBreakdownProvider =
    Provider<AsyncValue<List<CategorySlice>>>((ref) {
  return ref.watch(dashboardAggregateProvider).whenData((aggregate) {
    final entries = aggregate.categories;
    final grandTotal = entries.fold<double>(0, (sum, row) => sum + row.total);
    if (grandTotal <= 0) return const <CategorySlice>[];
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
  });
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

final topMerchantsProvider = Provider<AsyncValue<List<MerchantStat>>>((ref) {
  return ref.watch(dashboardAggregateProvider).whenData(
        (aggregate) => [
          for (final row in aggregate.merchants)
            MerchantStat(name: row.name, count: row.count, total: row.total),
        ],
      );
});

class MonthPoint {
  const MonthPoint({required this.month, required this.spend});

  final DateTime month;
  final double spend;
}

const _trendMonths = 6;

final sixMonthTrendProvider = Provider<AsyncValue<List<MonthPoint>>>((ref) {
  final anchor = ref.watch(dashboardPeriodProvider).trendAnchor;
  return ref.watch(dashboardAggregateProvider).whenData((aggregate) {
    final points = <MonthPoint>[];
    for (var i = _trendMonths - 1; i >= 0; i--) {
      final month = DateTime(anchor.year, anchor.month - i);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      points.add(
        MonthPoint(month: month, spend: aggregate.trendByMonth[key] ?? 0),
      );
    }
    return points;
  });
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
  final items = ref.watch(recurringSeriesProvider).valueOrNull ?? const [];
  final upcoming = items
      .where((item) => item.series.status != 'inactive')
      .map((item) => item.series)
      .toList(growable: false)
    ..sort((a, b) => a.nextExpectedDate.compareTo(b.nextExpectedDate));
  return upcoming.take(3).toList(growable: false);
});

/// Shared controller provider for shell tab index (0=Home, 1=Activity, 2=Sort, 3=Trends).
final homeTabControllerProvider = StateProvider<int>((ref) => 0);

/// Dynamic greeting based on time of day.
final dashboardGreetingProvider = Provider<String>((ref) {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
});

/// Derived financial status subline based on actual spend/budget metrics.
final dashboardStatusSublineProvider = Provider<String>((ref) {
  final mom = ref.watch(monthOverMonthSpendProvider).valueOrNull;
  if (mom != null && mom.pctChange != null) {
    final pct = (mom.pctChange! * 100).abs().toStringAsFixed(0);
    if (mom.pctChange! < 0) {
      return '$pct% lower spend than last month';
    } else if (mom.pctChange! > 0) {
      return '$pct% higher spend than last month';
    }
  }
  final safeToday = ref.watch(safeTodayValueProvider).valueOrNull;
  if (safeToday != null && safeToday >= 0) {
    return 'Budget on track today';
  }
  return 'Track your daily activity';
});
