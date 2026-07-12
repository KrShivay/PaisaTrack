import 'dart:convert';

import '../../data/db/database.dart';
import 'assistant_intent.dart';

sealed class AssistantQueryResult {
  const AssistantQueryResult();
}

class TotalQueryResult extends AssistantQueryResult {
  const TotalQueryResult({
    required this.value,
    required this.count,
    required this.label,
  });
  final double value;
  final int count;
  final String label;
}

class BreakdownItem {
  const BreakdownItem(this.label, this.total);
  final String label;
  final double total;
}

class BreakdownQueryResult extends AssistantQueryResult {
  const BreakdownQueryResult(this.items);
  final List<BreakdownItem> items;
}

class ComparisonQueryResult extends AssistantQueryResult {
  const ComparisonQueryResult({required this.current, required this.previous});
  final double current;
  final double previous;
  double get delta => current - previous;
  double? get percent => previous == 0 ? null : delta / previous;
}

class RecurringQueryItem {
  const RecurringQueryItem(this.label, this.amount, this.date);
  final String label;
  final double amount;
  final DateTime date;
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
    final all = await database.select(database.transactions).get();
    final merchants = {
      for (final row in await database.select(database.merchants).get())
        row.id: row.canonicalName,
    };
    return all.where((row) {
      final timestamp =
          DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true);
      if (timestamp.isBefore(range.start) || !timestamp.isBefore(range.end)) {
        return false;
      }
      if (row.isDeleted || row.duplicateOfTxnId != null) return false;
      if (intent.categoryId != null && row.categoryId != intent.categoryId) {
        return false;
      }
      if (intent.direction != null && row.direction != intent.direction) {
        return false;
      }
      if (intent.merchant != null) {
        final literal = intent.merchant!.toLowerCase();
        final stored =
            (merchants[row.merchantId] ?? row.merchantRaw ?? '').toLowerCase();
        if (!stored.contains(literal)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<TotalQueryResult> _total(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final values = rows
        .where((row) => _included(row, intent.metric))
        .map((row) => _signed(row, intent.metric))
        .toList();
    final value = switch (intent.aggregation) {
      AssistantAggregation.count => values.length.toDouble(),
      AssistantAggregation.average =>
        values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length,
      _ => values.fold<double>(0, (sum, value) => sum + value),
    };
    return TotalQueryResult(
      value: value,
      count: values.length,
      label: intent.range!.label,
    );
  }

  Future<BreakdownQueryResult> _breakdown(AssistantIntent intent) async {
    final rows = await _transactions(intent, intent.range!);
    final categories = {
      for (final row in await database.select(database.categories).get())
        row.id: row.name,
    };
    final totals = <String, double>{};
    for (final row in rows.where((row) => _included(row, intent.metric))) {
      final label = categories[row.categoryId] ?? 'Uncategorised';
      totals.update(
        label,
        (value) => value + _signed(row, intent.metric),
        ifAbsent: () => _signed(row, intent.metric),
      );
    }
    final items = totals.entries
        .map((e) => BreakdownItem(e.key, e.value))
        .toList()
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
        merchant: intent.merchant,
        direction: intent.direction,
      ),
    );
    return ComparisonQueryResult(
      current: current.value,
      previous: previous.value,
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
