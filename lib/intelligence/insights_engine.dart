import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/financial_calendar.dart';
import '../core/format.dart';
import '../data/analytics/financial_eligibility.dart';
import '../data/db/database.dart';
import '../data/models/source_currency.dart';
import 'claim.dart';

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
    required this.scope,
    required this.window,
    required this.metrics,
    required this.evidenceRows,
  });

  final String id;
  final String kind;
  final Map<String, Object?> payload;
  final Map<String, Object?> scope;
  final Map<String, Object?> window;
  final Map<String, num> metrics;
  final List<Transaction> evidenceRows;
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
      final scopedTransactions = await (_database.select(_database.transactions)
            ..where(
              (t) =>
                  t.ts.isBiggerOrEqualValue(
                    comparablePrevious.start.millisecondsSinceEpoch,
                  ) &
                  t.ts.isSmallerThanValue(
                    currentPeriod.end.millisecondsSinceEpoch,
                  ),
            ))
          .get();
      final eligibleTransactions = await (_database
              .select(_database.transactions)
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
      final categoryRows = await _database.select(_database.categories).get();
      final categories = {for (final row in categoryRows) row.id: row.name};
      final categoryEligibility = {
        for (final row in categoryRows) row.id: row.isSpending,
      };
      final transactions = eligibleTransactions;
      final specs = <_InsightSpec>[
        ..._duplicateSubscriptions(period, recurring, transactions),
        ..._fees(
          period,
          transactions,
          currentStart,
          currentEnd,
          categories,
          calendar,
        ),
        ..._priceCreep(period, recurring, transactions, calendar),
        ..._categoryDeltas(
          transactions,
          currentStart,
          currentEnd,
          comparablePrevious,
          categories,
          period,
          calendar,
        ),
        ..._missedAutopay(period, recurring, transactions, calendar),
      ];
      // No evidence means there is no observed claim to emit.
      specs.removeWhere((spec) => spec.evidenceRows.isEmpty);
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
        final claimScope = TypedClaim(
          version: 1,
          calculation: '${spec.kind}@1',
          id: spec.id,
          scope: spec.scope,
          window: spec.window,
          metrics: spec.metrics,
          evidenceIds: const [],
          evidenceCount: 0,
          truncated: false,
          inputHash: '',
          raw: const {},
        );
        final evidenceRows = ClaimEvidenceScope.select(
          claimScope,
          scopedTransactions,
          calendar: calendar,
          categoryEligibility: categoryEligibility,
        );
        final coverage = _coverage(
          ClaimEvidenceScope.select(
            claimScope,
            scopedTransactions,
            calendar: calendar,
            categoryEligibility: categoryEligibility,
            eligibleOnly: false,
          ),
          categoryEligibility,
        );
        await _database.into(_database.insights).insertOnConflictUpdate(
              InsightsCompanion.insert(
                id: spec.id,
                period: period,
                kind: spec.kind,
                payloadJson:
                    jsonEncode(_claimPayload(spec, coverage, evidenceRows)),
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
    List<Transaction> transactions,
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
      final evidenceRows = _seriesEvidence(
        sorted.first,
        transactions,
        matchAmount: false,
      );
      if (evidenceRows.isEmpty) continue;
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
        scope: {
          'merchant_ids': [sorted.first.merchantId],
          'currency_code': sorted.first.currencyCode,
          'currency_symbol': sorted.first.currencySymbol,
        },
        window: _windowForRows(evidenceRows, partial: false),
        metrics: {
          'monthly_total': evidenceRows.fold<double>(
            0,
            (sum, row) => sum + row.amount,
          ),
          'series_count': evidenceRows.length,
        },
        evidenceRows: evidenceRows,
      );
    }
  }

  Iterable<_InsightSpec> _fees(
    String period,
    List<Transaction> transactions,
    DateTime currentStart,
    DateTime currentEnd,
    Map<String, String> categories,
    FinancialCalendar calendar,
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
        scope: {
          'category_ids': categories.entries
              .where(
                (entry) =>
                    entry.key == 'fees_charges' ||
                    entry.value == 'Fees & Charges',
              )
              .map((entry) => entry.key)
              .toList()
            ..sort(),
          'currency_code': first.currencyCode,
          'currency_symbol': first.currencySymbol,
        },
        window: _window(
          currentStart,
          currentEnd.subtract(const Duration(microseconds: 1)),
          partial:
              currentEnd.isBefore(calendar.monthContaining(currentStart).end),
        ),
        metrics: {
          'total': rows.fold<double>(0, (sum, txn) => sum + txn.amount),
        },
        evidenceRows: rows,
      );
    }
  }

  Iterable<_InsightSpec> _priceCreep(
    String period,
    List<RecurringSery> recurring,
    List<Transaction> transactions,
    FinancialCalendar calendar,
  ) sync* {
    for (final series in recurring) {
      final evidenceRows = _seriesEvidence(series, transactions)
        ..sort((a, b) => a.ts.compareTo(b.ts));
      if (evidenceRows.length > 1 && evidenceRows.first.amount > 0) {
        final expected = evidenceRows.first.amount;
        final last = evidenceRows.last.amount;
        if ((last - expected).abs() <= expected * 0.05) continue;
        yield _InsightSpec(
          id: 'price_creep:$period:${series.id}',
          kind: 'price_creep',
          payload: _seriesPayload(series),
          scope: {
            'merchant_id': series.merchantId,
            'currency_code': series.currencyCode,
            'currency_symbol': series.currencySymbol,
          },
          window: _windowForRows(evidenceRows, partial: false),
          metrics: {
            'expected_amount': expected,
            'last_amount': last,
          },
          evidenceRows: evidenceRows,
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
    final groupedRows = <String, List<Transaction>>{};
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
      groupedRows.putIfAbsent(key, () => []).add(txn);
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
        scope: {
          'category_id': categoryId,
          'currency_code': currency.code,
          'currency_symbol': currency.symbol,
        },
        window: {
          'current': [
            _dateLabel(calendar, currentStart),
            _dateLabel(
              calendar,
              currentEnd.subtract(const Duration(microseconds: 1)),
            ),
          ],
          'previous': [
            _dateLabel(calendar, previousPeriod.start),
            _dateLabel(
              calendar,
              previousPeriod.end.subtract(const Duration(microseconds: 1)),
            ),
          ],
          'partial': currentEnd.isBefore(
            calendar.monthContaining(currentStart).end,
          ),
        },
        metrics: {
          'current_total': currentAmount,
          'previous_total': previousAmount,
          'delta_fraction': delta,
        },
        evidenceRows: groupedRows[key] ?? const [],
      );
    }
  }

  Iterable<_InsightSpec> _missedAutopay(
    String period,
    List<RecurringSery> recurring,
    List<Transaction> transactions,
    FinancialCalendar calendar,
  ) sync* {
    for (final series in recurring.where(
      (row) => row.status == 'missed' && row.kind != 'income',
    )) {
      final evidenceRows = _seriesEvidence(series, transactions);
      if (evidenceRows.isEmpty) continue;
      final average = evidenceRows.fold<double>(
            0,
            (sum, row) => sum + row.amount,
          ) /
          evidenceRows.length;
      yield _InsightSpec(
        id: 'missed_autopay:$period:${series.id}',
        kind: 'missed_autopay',
        payload: _seriesPayload(series),
        scope: {
          'merchant_id': series.merchantId,
          'currency_code': series.currencyCode,
          'currency_symbol': series.currencySymbol,
        },
        window: _windowForRows(evidenceRows, partial: false),
        metrics: {'expected_amount': average},
        evidenceRows: evidenceRows,
      );
    }
  }

  Map<String, Object?> _coverage(
    List<Transaction> rows,
    Map<String, bool> categoryEligibility,
  ) {
    final excluded = <String, int>{
      'not_settled': 0,
      'owned_transfer': 0,
      'analytics_excluded': 0,
      'non_spending': 0,
      'credit': 0,
    };
    var unreviewed = 0;
    var unknownCurrency = 0;
    for (final row in rows) {
      if (row.status == 'needs_review' || row.status == 'asked') unreviewed++;
      final eligible = FinancialEligibility.includesSpendingDebit(
        row,
        categoryIsSpending: row.categoryId == null ||
            categoryEligibility[row.categoryId] != false,
      );
      String? reason;
      if (!eligible &&
          (row.isDeleted ||
              row.isNotTransaction ||
              row.duplicateOfTxnId != null ||
              row.lifecycleState != 'settled')) {
        reason = 'not_settled';
      } else if (!eligible && row.ownedTransferId != null) {
        reason = 'owned_transfer';
      } else if (!eligible && row.isAnalyticsExcluded) {
        reason = 'analytics_excluded';
      } else if (!eligible &&
          row.categoryId != null &&
          categoryEligibility[row.categoryId] == false) {
        reason = 'non_spending';
      } else if (!eligible && row.direction != 'debit') {
        reason = 'credit';
      }
      if (reason != null) {
        excluded[reason] = excluded[reason]! + 1;
      } else if (row.currencyCode == null) {
        unknownCurrency++;
      }
    }
    return {
      'rows': rows.length,
      'unreviewed': unreviewed,
      'excluded': excluded,
      'unknown_currency': unknownCurrency,
    };
  }

  List<Transaction> _seriesEvidence(
    RecurringSery series,
    List<Transaction> transactions, {
    bool matchAmount = true,
  }) =>
      transactions.where((row) {
        final sameMerchant = row.merchantId == series.merchantId;
        final sameCurrency = sourceCurrencyBucket(row) ==
            SourceCurrency(
              code: series.currencyCode,
              symbol: series.currencySymbol,
            ).bucketKey;
        return sameMerchant && sameCurrency;
      }).toList();

  Map<String, Object?> _claimPayload(
    _InsightSpec spec,
    Map<String, Object?> coverage,
    List<Transaction> evidenceRows,
  ) {
    final ids = evidenceRows.map((row) => row.id).toSet().toList()..sort();
    final selectedIds = ids.take(50).toList();
    const validator = ClaimValidator();
    return {
      ...spec.payload,
      'claim': {
        'v': 1,
        'calc': '${spec.kind}@1',
        'claim_id': spec.id,
        'basis': 'observed',
        'scope': spec.scope,
        'window': spec.window,
        'metrics': spec.metrics,
        'evidence': {
          'ids': selectedIds,
          'total_count': ids.length,
          'truncated': ids.length > selectedIds.length,
        },
        'coverage': coverage,
        'input_hash': validator.inputHash(evidenceRows),
      },
    };
  }

  Map<String, Object?> _window(
    DateTime? start,
    DateTime? end, {
    required bool partial,
  }) =>
      {
        'current': start == null || end == null
            ? null
            : [
                _dateLabel(_calendar ?? FinancialCalendar(), start),
                _dateLabel(_calendar ?? FinancialCalendar(), end),
              ],
        'previous': null,
        'partial': partial,
      };

  Map<String, Object?> _windowForRows(
    List<Transaction> rows, {
    required bool partial,
  }) {
    final timestamps = rows.map((row) => row.ts).toList()..sort();
    return _window(
      DateTime.fromMillisecondsSinceEpoch(timestamps.first, isUtc: true),
      DateTime.fromMillisecondsSinceEpoch(timestamps.last, isUtc: true),
      partial: partial,
    );
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
