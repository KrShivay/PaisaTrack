import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../data/db/database.dart';

/// Incremental weekly-category and monthly-merchant anomaly scanner.
class AnomalyDetector {
  const AnomalyDetector(
    this._database, {
    this.amountFloor = defaultAmountFloor,
  });

  static const minimumBaselinePeriods = 8;
  static const sigmaThreshold = 2.5;
  static const defaultAmountFloor = 500.0;

  final AppDatabase _database;
  final double amountFloor;

  /// Processes the UTC week/month containing [today] exactly once per key.
  Future<int> run({DateTime? today}) {
    final now = (today ?? DateTime.now()).toUtc();
    return _database.transaction(() async {
      final weekStart = _weekStart(now);
      final monthStart = DateTime.utc(now.year, now.month);
      final nextWeek = weekStart.add(const Duration(days: 7));
      final nextMonth = DateTime.utc(now.year, now.month + 1);
      var flags = 0;
      flags += await _processPeriod(
        keyPrefix: 'cat:',
        suffix: ':week',
        start: weekStart,
        end: nextWeek,
        period: _dateKey(weekStart),
        identityOf: (txn) => txn.categoryId,
      );
      flags += await _processPeriod(
        keyPrefix: 'mer:',
        suffix: ':month',
        start: monthStart,
        end: nextMonth,
        period: '${now.year}-${now.month.toString().padLeft(2, '0')}',
        identityOf: (txn) => txn.merchantId,
      );
      return flags;
    });
  }

  Future<int> _processPeriod({
    required String keyPrefix,
    required String suffix,
    required DateTime start,
    required DateTime end,
    required String period,
    required String? Function(Transaction txn) identityOf,
  }) async {
    final rows = await (_database.select(_database.transactions)
          ..where(
            (t) =>
                t.ts.isBiggerOrEqualValue(start.millisecondsSinceEpoch) &
                t.ts.isSmallerThanValue(end.millisecondsSinceEpoch) &
                t.isAnalyticsExcluded.equals(false) &
                t.ownedTransferId.isNull() &
                t.isDeleted.equals(false) &
                t.duplicateOfTxnId.isNull(),
          ))
        .get();
    final groups = <String, List<Transaction>>{};
    for (final txn in rows) {
      final identity = identityOf(txn);
      if (identity != null) groups.putIfAbsent(identity, () => []).add(txn);
    }

    final activeSeries = await (_database.select(_database.recurringSeries)
          ..where((s) => s.status.equals('active')))
        .get();
    final recurringMerchantIds = {for (final s in activeSeries) s.merchantId};

    var flags = 0;
    for (final entry in groups.entries) {
      final key = '$keyPrefix${entry.key}$suffix';
      final existing = await (_database.select(_database.baselines)
            ..where((b) => b.key.equals(key)))
          .getSingleOrNull();
      if (existing != null && !existing.updatedAt.toUtc().isBefore(start)) {
        continue;
      }
      final aggregate =
          entry.value.fold<double>(0, (sum, txn) => sum + txn.amount);
      final threshold = existing == null
          ? double.infinity
          : existing.mean + sigmaThreshold * existing.std;

      final isBelowFloor = aggregate < amountFloor;
      final isRecurring = keyPrefix == 'mer:'
          ? recurringMerchantIds.contains(entry.key)
          : false;
      final isSuppressed = isBelowFloor || isRecurring;
      final suppressionReason = isBelowFloor
          ? 'below_floor'
          : (isRecurring ? 'recurring_series' : null);

      if (existing != null &&
          existing.n >= minimumBaselinePeriods &&
          aggregate > threshold) {
        final contributors = [...entry.value]
          ..sort((a, b) => b.amount.compareTo(a.amount));
        await _database.into(_database.insights).insertOnConflictUpdate(
              InsightsCompanion.insert(
                id: 'anomaly:$key:$period',
                period: period,
                kind: 'anomaly',
                payloadJson: jsonEncode({
                  'baseline_key': key,
                  'aggregate': aggregate,
                  'threshold': threshold,
                  'top_transaction_ids': [
                    for (final txn in contributors.take(3)) txn.id,
                  ],
                  'suppressed': isSuppressed,
                  'suppression_reason': suppressionReason,
                }),
              ),
            );
        if (!isSuppressed) flags++;
      }
      final updated = _update(existing, aggregate);
      await _database.into(_database.baselines).insertOnConflictUpdate(
            BaselinesCompanion.insert(
              key: key,
              mean: updated.$1,
              std: updated.$2,
              n: updated.$3,
              updatedAt: start,
            ),
          );
    }
    return flags;
  }

  (double, double, int) _update(Baseline? baseline, double value) {
    if (baseline == null) return (value, 0, 1);
    final nextN = baseline.n + 1;
    final delta = value - baseline.mean;
    final nextMean = baseline.mean + delta / nextN;
    final oldM2 = baseline.std * baseline.std * baseline.n;
    final nextM2 = oldM2 + delta * (value - nextMean);
    return (nextMean, math.sqrt(nextM2 / nextN), nextN);
  }

  DateTime _weekStart(DateTime value) {
    final day = DateTime.utc(value.year, value.month, value.day);
    return day.subtract(Duration(days: value.weekday - DateTime.monday));
  }

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
