import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/db/database.dart';

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

/// Precomputes deterministic, no-LLM insights for one UTC calendar month.
class InsightsEngine {
  const InsightsEngine(this._database);

  static const _ownedKinds = {
    'duplicate_subscription',
    'fees_total',
    'price_creep',
    'category_delta',
    'missed_autopay',
  };
  static const categoryDeltaThreshold = 0.10;

  final AppDatabase _database;

  /// Replaces this engine's insights for the current period atomically.
  ///
  /// Existing anomaly/forecast rows are owned by their dedicated engines and
  /// remain untouched. A user's dismissed state survives payload refreshes.
  Future<InsightsRunResult> run({DateTime? today}) {
    final now = (today ?? DateTime.now()).toUtc();
    final currentStart = DateTime.utc(now.year, now.month);
    final nextMonth = DateTime.utc(now.year, now.month + 1);
    final previousStart = DateTime.utc(now.year, now.month - 1);
    final period = _monthKey(currentStart);

    return _database.transaction(() async {
      final recurring = await _database.select(_database.recurringSeries).get();
      final transactions = await (_database.select(_database.transactions)
            ..where(
              (t) =>
                  t.ts.isBiggerOrEqualValue(
                    previousStart.millisecondsSinceEpoch,
                  ) &
                  t.ts.isSmallerThanValue(nextMonth.millisecondsSinceEpoch) &
                  t.direction.equals('debit') &
                  t.isAnalyticsExcluded.equals(false) &
                  t.ownedTransferId.isNull() &
                  t.isDeleted.equals(false) &
                  t.duplicateOfTxnId.isNull(),
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
          nextMonth,
          categories,
          period,
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
      byMerchant.putIfAbsent(series.merchantId, () => []).add(series);
    }
    for (final entry in byMerchant.entries) {
      if (entry.value.length < 2) continue;
      final sorted = [...entry.value]..sort((a, b) => a.id.compareTo(b.id));
      yield _InsightSpec(
        id: 'duplicate_subscription:$period:${entry.key}',
        kind: 'duplicate_subscription',
        payload: {
          'merchant_id': entry.key,
          'label': sorted.first.label,
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
    final rows = fees.toList(growable: false);
    if (rows.isEmpty) return;
    yield _InsightSpec(
      id: 'fees_total:$period',
      kind: 'fees_total',
      payload: {
        'total': rows.fold<double>(0, (sum, txn) => sum + txn.amount),
        'count': rows.length,
        'transaction_ids': [for (final txn in rows) txn.id]..sort(),
      },
    );
  }

  Iterable<_InsightSpec> _priceCreep(
    String period,
    List<RecurringSery> recurring,
  ) sync* {
    for (final series in recurring) {
      final diff = (series.lastAmount - series.expectedAmount).abs();
      final relChange = series.expectedAmount > 0 ? diff / series.expectedAmount : 0.0;
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
    DateTime nextMonth,
    Map<String, String> categories,
    String period,
  ) sync* {
    final current = <String, double>{};
    final previous = <String, double>{};
    for (final txn in transactions) {
      final categoryId = txn.categoryId;
      if (categoryId == null) continue;
      final date = _date(txn);
      final target = !date.isBefore(currentStart) && date.isBefore(nextMonth)
          ? current
          : previous;
      target[categoryId] = (target[categoryId] ?? 0) + txn.amount;
    }
    final ids = {...current.keys, ...previous.keys}.toList()..sort();
    for (final categoryId in ids) {
      final currentAmount = current[categoryId] ?? 0;
      final previousAmount = previous[categoryId] ?? 0;
      if (previousAmount == 0) continue;
      final delta = (currentAmount - previousAmount) / previousAmount;
      if (delta.abs() <= categoryDeltaThreshold) continue;
      yield _InsightSpec(
        id: 'category_delta:$period:$categoryId',
        kind: 'category_delta',
        payload: {
          'category_id': categoryId,
          'category_name': categories[categoryId] ?? categoryId,
          'current_total': currentAmount,
          'previous_total': previousAmount,
          'delta_fraction': delta,
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
        'summary': '${series.label} ₹${series.expectedAmount.round()} → ₹${series.lastAmount.round()}',
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

  String _monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
}
