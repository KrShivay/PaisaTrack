import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/financial_calendar.dart';
import '../core/format.dart';
import '../data/analytics/financial_eligibility.dart';
import '../data/db/database.dart';
import '../data/models/source_currency.dart';

/// Result of one deterministic insight recomputation.
class InsightsRunResult {
  const InsightsRunResult({
    required this.period,
    required this.generated,
    required this.upstream,
  });

  final String period;
  final int generated;

  /// Anomaly/forecast insights already produced by their dedicated engines.
  final int upstream;
}

class _InsightSpec {
  const _InsightSpec({
    required this.id,
    required this.kind,
    required this.payload,
  });

  final String id;
  final String kind;
  final Map<String, Object?> payload;
}

/// Precomputes deterministic, no-LLM insights for one local calendar month.
class InsightsEngine {
  const InsightsEngine(this._database, {FinancialCalendar? calendar})
      : _calendar = calendar;

  static const _ownedKinds = {
    'duplicate_subscription',
    'fees_total',
    'price_creep',
    'category_delta',
    'missed_autopay',
  };
  static const categoryDeltaThreshold = 0.10;

  final AppDatabase _database;
  final FinancialCalendar? _calendar;

  /// Replaces this engine's insights for the current period atomically.
  ///
  /// Existing anomaly/forecast rows are owned by their dedicated engines and
  /// remain untouched. A user's dismissed state survives payload refreshes.
  Future<InsightsRunResult> run({DateTime? today}) {
    final calendar = _calendar ?? FinancialCalendar();
    final instant = today ?? DateTime.now();
    final now = calendar.localDate(instant);
    final currentPeriod = calendar.monthContaining(instant);
    final currentStart = currentPeriod.start;
    final currentEnd = calendar.throughToday(currentPeriod, instant).end;
    final fullPrevious = calendar.month(now.year, now.month - 1);
    final comparablePrevious = calendar.comparablePrior(
      current: currentPeriod,
      prior: fullPrevious,
      now: instant,
    );
    final period = calendar.monthKey(instant);

    return _database.transaction(() async {
      final recurring = await _database.select(_database.recurringSeries).get();
      final transactions = await (_database.select(_database.transactions)
            ..where(
              (t) =>
                  t.ts.isBiggerOrEqualValue(
                    comparablePrevious.start.millisecondsSinceEpoch,
                  ) &
                  t.ts.isSmallerThanValue(
                    currentPeriod.end.millisecondsSinceEpoch,
                  ) &
                  FinancialEligibility.spendingDebit(t, _database.categories),
            ))
          .get();
      final categories = {
        for (final row in await _database.select(_database.categories).get())
          row.id: row.name,
      };
      final specs = <_InsightSpec>[
        ..._duplicateSubscriptions(period, recurring),
        ..._fees(period, transactions, currentStart, categories),
        ..._priceCreep(period, recurring),
        ..._categoryDeltas(
          transactions,
          currentStart,
          currentEnd,
          comparablePrevious,
          categories,
          period,
          calendar,
        ),
        ..._missedAutopay(period, recurring),
      ];
      specs.sort((a, b) => a.id.compareTo(b.id));

      final existing = await (_database.select(_database.insights)
            ..where((i) => i.period.equals(period)))
          .get();
      final existingById = {for (final row in existing) row.id: row};
      final nextIds = specs.map((spec) => spec.id).toSet();
      await (_database.delete(_database.insights)
            ..where(
              (i) =>
                  i.period.equals(period) &
                  i.kind.isIn(_ownedKinds) &
                  i.id.isNotIn(nextIds),
            ))
          .go();

      for (final spec in specs) {
        await _database.into(_database.insights).insertOnConflictUpdate(
              InsightsCompanion.insert(
                id: spec.id,
                period: period,
                kind: spec.kind,
                payloadJson: jsonEncode(spec.payload),
                dismissed: Value(existingById[spec.id]?.dismissed ?? false),
              ),
            );
      }

      final upstream = existing.where(
        (row) => row.kind == 'anomaly' || row.kind == 'forecast',
      );
      return InsightsRunResult(
        period: period,
        generated: specs.length,
        upstream: upstream.length,
      );
    });
  }

  Iterable<_InsightSpec> _duplicateSubscriptions(
    String period,
    List<RecurringSery> recurring,
  ) sync* {
    final byMerchant = <String, List<RecurringSery>>{};
    for (final series in recurring) {
      if (series.kind != 'subscription' || series.status != 'active') continue;
      final currency = SourceCurrency(
        code: series.currencyCode,
        symbol: series.currencySymbol,
      );
      byMerchant
          .putIfAbsent('${series.merchantId}|${currency.bucketKey}', () => [])
          .add(series);
    }
    for (final entry in byMerchant.entries) {
      if (entry.value.length < 2) continue;
      final sorted = [...entry.value]..sort((a, b) => a.id.compareTo(b.id));
      yield _InsightSpec(
        id: 'duplicate_subscription:$period:${entry.key}',
        kind: 'duplicate_subscription',
        payload: {
          'merchant_id': sorted.first.merchantId,
          'label': sorted.first.label,
          'currency_code': sorted.first.currencyCode,
          'currency_symbol': sorted.first.currencySymbol,
          'series_ids': [for (final series in sorted) series.id],
          'monthly_total': sorted.fold<double>(
            0,
            (sum, series) => sum + _monthlyAmount(series),
          ),
        },
      );
    }
  }

  Iterable<_InsightSpec> _fees(
    String period,
    List<Transaction> transactions,
    DateTime currentStart,
    Map<String, String> categories,
  ) sync* {
    final fees = transactions.where(
      (txn) =>
          !_date(txn).isBefore(currentStart) &&
          (txn.categoryId == 'fees_charges' ||
              categories[txn.categoryId] == 'Fees & Charges'),
    );
    final byCurrency = <String, List<Transaction>>{};
    for (final txn in fees) {
      final bucket = SourceCurrency(
        code: txn.currencyCode,
        symbol: txn.currencySymbol,
      ).bucketKey;
      byCurrency.putIfAbsent(bucket, () => []).add(txn);
    }
    for (final entry in byCurrency.entries) {
      final rows = entry.value;
      final first = rows.first;
      yield _InsightSpec(
        id: 'fees_total:$period:${entry.key}',
        kind: 'fees_total',
        payload: {
          'total': rows.fold<double>(0, (sum, txn) => sum + txn.amount),
          'currency_code': first.currencyCode,
          'currency_symbol': first.currencySymbol,
          'count': rows.length,
          'transaction_ids': [for (final txn in rows) txn.id]..sort(),
        },
      );
    }
  }

  Iterable<_InsightSpec> _priceCreep(
    String period,
    List<RecurringSery> recurring,
  ) sync* {
    for (final series in recurring) {
      final diff = (series.lastAmount - series.expectedAmount).abs();
      final relChange =
          series.expectedAmount > 0 ? diff / series.expectedAmount : 0.0;
      if (series.amountTrend == 'rising' || relChange > 0.05) {
        yield _InsightSpec(
          id: 'price_creep:$period:${series.id}',
          kind: 'price_creep',
          payload: _seriesPayload(series),
        );
      }
    }
  }

  Iterable<_InsightSpec> _categoryDeltas(
    List<Transaction> transactions,
    DateTime currentStart,
    DateTime currentEnd,
    FinancialPeriod previousPeriod,
    Map<String, String> categories,
    String period,
    FinancialCalendar calendar,
  ) sync* {
    final current = <String, double>{};
    final previous = <String, double>{};
    final currencies = <String, SourceCurrency>{};
    for (final txn in transactions) {
      final categoryId = txn.categoryId;
      if (categoryId == null) continue;
      final instant = _date(txn);
      final target =
          !instant.isBefore(currentStart) && instant.isBefore(currentEnd)
              ? current
              : !instant.isBefore(previousPeriod.start) &&
                      instant.isBefore(previousPeriod.end)
                  ? previous
                  : null;
      if (target == null) continue;
      final currency = SourceCurrency(
        code: txn.currencyCode,
        symbol: txn.currencySymbol,
      );
      final key = '$categoryId\u0000${currency.bucketKey}';
      currencies[key] = currency;
      target[key] = (target[key] ?? 0) + txn.amount;
    }
    final keys = {...current.keys, ...previous.keys}.toList()..sort();
    for (final key in keys) {
      final categoryId = key.split('\u0000').first;
      final currency = currencies[key]!;
      final currentAmount = current[key] ?? 0;
      final previousAmount = previous[key] ?? 0;
      if (previousAmount == 0) continue;
      final delta = (currentAmount - previousAmount) / previousAmount;
      if (delta.abs() <= categoryDeltaThreshold) continue;
      yield _InsightSpec(
        id: 'category_delta:$period:${key.replaceAll('\u0000', ':')}',
        kind: 'category_delta',
        payload: {
          'category_id': categoryId,
          'category_name': categories[categoryId] ?? categoryId,
          'currency_code': currency.code,
          'currency_symbol': currency.symbol,
          'current_total': currentAmount,
          'previous_total': previousAmount,
          'delta_fraction': delta,
          // Inclusive local dates make both windows checkable; SQL uses
          // half-open UTC instants for the actual query.
          'current_start': _dateLabel(calendar, currentStart),
          'current_end': _dateLabel(
            calendar,
            currentEnd.subtract(const Duration(microseconds: 1)),
          ),
          'previous_start': _dateLabel(calendar, previousPeriod.start),
          'previous_end': _dateLabel(
            calendar,
            previousPeriod.end.subtract(const Duration(microseconds: 1)),
          ),
        },
      );
    }
  }

  Iterable<_InsightSpec> _missedAutopay(
    String period,
    List<RecurringSery> recurring,
  ) sync* {
    for (final series in recurring.where(
      (row) => row.status == 'missed' && row.kind != 'income',
    )) {
      yield _InsightSpec(
        id: 'missed_autopay:$period:${series.id}',
        kind: 'missed_autopay',
        payload: _seriesPayload(series),
      );
    }
  }

  Map<String, Object?> _seriesPayload(RecurringSery series) => {
        'series_id': series.id,
        'merchant_id': series.merchantId,
        'label': series.label,
        'expected_amount': series.expectedAmount,
        'last_amount': series.lastAmount,
        'summary':
            '${series.label} ${formatSourceAmount(series.expectedAmount, currencyCode: series.currencyCode, currencySymbol: series.currencySymbol)} → ${formatSourceAmount(series.lastAmount, currencyCode: series.currencyCode, currencySymbol: series.currencySymbol)}',
        'currency_code': series.currencyCode,
        'currency_symbol': series.currencySymbol,
        'next_expected_date': series.nextExpectedDate.toIso8601String(),
        'kind': series.kind,
      };

  double _monthlyAmount(RecurringSery series) => switch (series.period) {
        'weekly' => series.expectedAmount * 52 / 12,
        'quarterly' => series.expectedAmount / 3,
        'yearly' => series.expectedAmount / 12,
        _ => series.expectedAmount,
      };

  DateTime _date(Transaction txn) =>
      DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true);

  String _dateLabel(FinancialCalendar calendar, DateTime instant) {
    final date = calendar.localDate(instant);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
