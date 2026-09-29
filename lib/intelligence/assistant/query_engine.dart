import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/database.dart';
import '../../data/models/source_currency.dart';
import 'assistant_intent.dart';

sealed class AssistantQueryResult {
  const AssistantQueryResult();
}

class TotalQueryResult extends AssistantQueryResult {
  const TotalQueryResult({
    required this.value,
    required this.count,
    required this.label,
    this.currencyBuckets = const [],
  });
  final double value;
  final int count;
  final String label;
  final List<AssistantCurrencyBucket> currencyBuckets;
}

class AssistantCurrencyBucket {
  const AssistantCurrencyBucket({
    required this.amount,
    required this.count,
    this.currencyCode,
    this.currencySymbol,
  });
  final double amount;
  final int count;
  final String? currencyCode;
  final String? currencySymbol;
  String get key =>
      SourceCurrency(code: currencyCode, symbol: currencySymbol).bucketKey;
}

class BreakdownItem {
  const BreakdownItem(
    this.label,
    this.total, {
    this.currencyCode,
    this.currencySymbol,
  });
  final String label;
  final double total;
  final String? currencyCode;
  final String? currencySymbol;
}

class BreakdownQueryResult extends AssistantQueryResult {
  const BreakdownQueryResult(this.items);
  final List<BreakdownItem> items;
}

class ComparisonQueryResult extends AssistantQueryResult {
  const ComparisonQueryResult({
    required this.current,
    required this.previous,
    this.currencyBuckets = const [],
  });
  final double current;
  final double previous;
  final List<
      ({
        double current,
        double previous,
        String? currencyCode,
        String? currencySymbol
      })> currencyBuckets;
  double get delta => current - previous;
  double? get percent => previous == 0 ? null : delta / previous;
}

class RecurringQueryItem {
  const RecurringQueryItem(
    this.label,
    this.amount,
    this.date, {
    this.currencyCode,
    this.currencySymbol,
  });
  final String label;
  final double amount;
  final DateTime date;
  final String? currencyCode;
  final String? currencySymbol;
}

class RecurringQueryResult extends AssistantQueryResult {
  const RecurringQueryResult(this.items);
  final List<RecurringQueryItem> items;
}

class InsightQueryItem {
  const InsightQueryItem(this.kind, this.figures);
  final String kind;
  final Map<String, num> figures;
}

class InsightsQueryResult extends AssistantQueryResult {
  const InsightsQueryResult(this.items);
  final List<InsightQueryItem> items;
}

class AssistantQueryEngine {
  const AssistantQueryEngine(this.database);
  final AppDatabase database;

  Future<AssistantQueryResult> run(AssistantIntent intent) =>
      switch (intent.kind) {
        AssistantIntentKind.periodTotal ||
        AssistantIntentKind.merchantLookup =>
          _total(intent),
        AssistantIntentKind.categoryBreakdown => _breakdown(intent),
        AssistantIntentKind.monthOverMonth => _comparison(intent),
        AssistantIntentKind.upcomingRecurring => _recurring(intent),
        AssistantIntentKind.activeInsights => _insights(intent),
      };

  Future<List<Transaction>> _transactions(
    AssistantIntent intent,
    AssistantTimeRange range,
  ) async {
    final categories = await database.select(database.categories).get();
    final selectedIds = intent.categoryIds.isNotEmpty
        ? intent.categoryIds.toSet()
        : {if (intent.categoryId != null) intent.categoryId!};
    final categoryParents = {
      for (final category in categories) category.id: category.parentId,
    };
    final categoryScope = _descendantCategoryIds(selectedIds, categoryParents);
    final nonSpendingIds = categories
        .where((category) => !category.isSpending)
        .map((category) => category.id)
        .toSet();
    final query = database.select(database.transactions)
      ..where((row) {
        Expression<bool> predicate =
            row.ts.isBiggerOrEqualValue(range.start.millisecondsSinceEpoch) &
                row.ts.isSmallerThanValue(range.end.millisecondsSinceEpoch) &
                row.isDeleted.equals(false) &
                row.isNotTransaction.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.isAnalyticsExcluded.equals(false) &
                row.ownedTransferId.isNull() &
                row.lifecycleState.equals('settled');
        if (categoryScope.isNotEmpty) {
          predicate &= row.categoryId.isIn(categoryScope);
        }
        if (intent.metric == AssistantMetric.spend &&
            nonSpendingIds.isNotEmpty) {
          predicate &=
              row.categoryId.isNull() | row.categoryId.isNotIn(nonSpendingIds);
        }
        if (intent.direction != null) {
          predicate &= row.direction.equals(intent.direction!);
        }
        return predicate;
      });
    final rows = await query.get();
    if (intent.merchant == null) return rows;

    final merchantIds = rows
        .map((row) => row.merchantId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final merchants = <String, String>{};
    if (merchantIds.isNotEmpty) {
      final merchantQuery = database.select(database.merchants)
        ..where((row) => row.id.isIn(merchantIds));
      for (final row in await merchantQuery.get()) {
        merchants[row.id] = row.userLabel ?? row.canonicalName;
      }
    }
    final literal = intent.merchant!.toLowerCase();
    return rows.where((row) {
      if (intent.merchant != null) {
        final stored =
            (merchants[row.merchantId] ?? row.merchantRaw ?? '').toLowerCase();
        if (!stored.contains(literal)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<TotalQueryResult> _total(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final selected =
        rows.where((row) => _included(row, intent.metric)).toList();
    final grouped = <String, List<Transaction>>{};
    for (final row in selected) {
      grouped
          .putIfAbsent(
            SourceCurrency(
              code: row.currencyCode,
              symbol: row.currencySymbol,
            ).bucketKey,
            () => [],
          )
          .add(row);
    }
    final buckets = grouped.values.map((bucketRows) {
      final amounts = bucketRows.map((row) => _signed(row, intent.metric));
      final amount = switch (intent.aggregation) {
        AssistantAggregation.count => bucketRows.length.toDouble(),
        AssistantAggregation.average => amounts.isEmpty
            ? 0.0
            : amounts.reduce((a, b) => a + b) / bucketRows.length,
        _ => amounts.fold<double>(0, (sum, value) => sum + value),
      };
      final first = bucketRows.first;
      return AssistantCurrencyBucket(
        amount: amount,
        count: bucketRows.length,
        currencyCode: first.currencyCode,
        currencySymbol: first.currencySymbol,
      );
    }).toList(growable: false);
    final value = intent.aggregation == AssistantAggregation.count
        ? selected.length.toDouble()
        : buckets.length == 1
            ? buckets.single.amount
            : 0.0;
    return TotalQueryResult(
      value: value,
      count: selected.length,
      label: intent.range!.label,
      currencyBuckets: buckets,
    );
  }

  Future<BreakdownQueryResult> _breakdown(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final categories = {
      for (final row in await database.select(database.categories).get())
        row.id: row.name,
    };
    final totals =
        <(String, String), ({double amount, String? code, String? symbol})>{};
    for (final row in rows.where((row) => _included(row, intent.metric))) {
      final label = categories[row.categoryId] ?? 'Uncategorised';
      final currency =
          SourceCurrency(code: row.currencyCode, symbol: row.currencySymbol)
              .bucketKey;
      final key = (label, currency);
      final prior = totals[key];
      totals[key] = (
        amount: (prior?.amount ?? 0) + _signed(row, intent.metric),
        code: row.currencyCode,
        symbol: row.currencySymbol
      );
    }
    final items = totals.entries.map((e) {
      final label = e.key.$1;
      return BreakdownItem(
        label,
        e.value.amount,
        currencyCode: e.value.code,
        currencySymbol: e.value.symbol,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return BreakdownQueryResult(items);
  }

  Future<ComparisonQueryResult> _comparison(AssistantIntent intent) async {
    final current = await _total(intent);
    final previous = await _total(
      AssistantIntent(
        kind: AssistantIntentKind.periodTotal,
        metric: intent.metric,
        aggregation: AssistantAggregation.sum,
        range: intent.compareRange,
        categoryId: intent.categoryId,
        categoryIds: intent.categoryIds,
        categoryNames: intent.categoryNames,
        categoryName: intent.categoryName,
        merchant: intent.merchant,
        direction: intent.direction,
      ),
    );
    return ComparisonQueryResult(
      current: current.value,
      previous: previous.value,
      currencyBuckets: [
        for (final bucket in current.currencyBuckets)
          if (previous.currencyBuckets.any((prior) => prior.key == bucket.key))
            (
              current: bucket.amount,
              previous: previous.currencyBuckets
                  .firstWhere((prior) => prior.key == bucket.key)
                  .amount,
              currencyCode: bucket.currencyCode,
              currencySymbol: bucket.currencySymbol
            ),
      ],
    );
  }

  Future<RecurringQueryResult> _recurring(AssistantIntent intent) async {
    final range = intent.range!;
    final rows = await database.select(database.recurringSeries).get();
    final items = rows
        .where(
          (row) =>
              !row.nextExpectedDate.isBefore(range.start) &&
              row.nextExpectedDate.isBefore(range.end),
        )
        .map(
          (row) => RecurringQueryItem(
            row.label,
            row.expectedAmount,
            row.nextExpectedDate,
            currencyCode: row.currencyCode,
            currencySymbol: row.currencySymbol,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return RecurringQueryResult(items);
  }

  Future<InsightsQueryResult> _insights(AssistantIntent intent) async {
    final rows = await database.select(database.insights).get();
    final items = <InsightQueryItem>[];
    for (final row in rows.where((row) => !row.dismissed)) {
      if (intent.range != null) {
        final period = DateTime.tryParse('${row.period.substring(0, 7)}-01');
        if (period == null ||
            period.isBefore(intent.range!.start) ||
            !period.isBefore(intent.range!.end)) {
          continue;
        }
      }
      final decoded = _object(row.payloadJson);
      items.add(
        InsightQueryItem(row.kind, {
          for (final entry in decoded.entries)
            if (entry.value is num) entry.key: entry.value! as num,
        }),
      );
    }
    return InsightsQueryResult(items);
  }

  static bool _included(Transaction row, AssistantMetric metric) =>
      switch (metric) {
        AssistantMetric.spend => row.direction == 'debit',
        AssistantMetric.income => row.direction == 'credit',
        AssistantMetric.net => true,
      };

  static Set<String> _descendantCategoryIds(
    Set<String> selectedIds,
    Map<String, String?> parents,
  ) {
    final included = {...selectedIds};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in parents.entries) {
        if (!included.contains(entry.key) &&
            entry.value != null &&
            included.contains(entry.value)) {
          included.add(entry.key);
          changed = true;
        }
      }
    }
    return included;
  }

  static double _signed(Transaction row, AssistantMetric metric) =>
      metric == AssistantMetric.net && row.direction == 'debit'
          ? -row.amount
          : row.amount;
  static Map<String, Object?> _object(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, Object?> ? value : const {};
    } on FormatException {
      return const {};
    }
  }
}
