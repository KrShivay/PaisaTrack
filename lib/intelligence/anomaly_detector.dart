import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/financial_calendar.dart';
import '../data/analytics/financial_eligibility.dart';
import '../data/db/database.dart';
import '../data/models/source_currency.dart';
import '../data/repositories/feature_flag_repository.dart';

/// Deterministic weekly-category and monthly-merchant anomaly rebuild.
class AnomalyDetector {
  const AnomalyDetector(this._database, {FinancialCalendar? calendar})
      : _calendar = calendar;

  static const minimumBaselinePeriods = 8;
  static const weeklyBaselinePeriods = 12;
  static const monthlyBaselinePeriods = 6;
  static const sigmaThreshold = 2.5;
  static const defaultAmountFloor = 500.0;

  final AppDatabase _database;
  final FinancialCalendar? _calendar;

  /// Rebuilds completed-period statistics and current-period anomaly rows.
  Future<int> run({DateTime? today}) async {
    final calendar = _calendar ?? FinancialCalendar();
    final instant = (today ?? DateTime.now()).toUtc();
    final now = calendar.localDate(instant);
    final currentWeek = _weekContaining(now, calendar);
    final currentMonth = calendar.monthContaining(instant);
    final flags = await FeatureFlagRepository(_database).getFlags();
    final transactions = await (_database.select(_database.transactions)
          ..where(
            (t) =>
                t.ts.isSmallerThanValue(
                  currentMonth.end.millisecondsSinceEpoch,
                ) &
                FinancialEligibility.spendingDebit(t, _database.categories),
          ))
        .get();
    final recurring = await (_database.select(_database.recurringSeries)
          ..where((s) => s.status.equals('active')))
        .get();
    final recurringMerchants = {
      for (final row in recurring)
        '${row.merchantId}|${SourceCurrency(code: row.currencyCode, symbol: row.currencySymbol).bucketKey}',
    };
    final groups = <String, _AnomalyIdentity>{};
    for (final txn in transactions) {
      final bucket = SourceCurrency(
        code: txn.currencyCode,
        symbol: txn.currencySymbol,
      ).bucketKey;
      final date = DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true);
      if (txn.categoryId != null) {
        final key = 'cat:${txn.categoryId}|$bucket:week';
        groups
            .putIfAbsent(key, () => _AnomalyIdentity(key, weekly: true))
            .add(date, txn);
      }
      if (txn.merchantId != null) {
        final key = 'mer:${txn.merchantId}|$bucket:month';
        groups
            .putIfAbsent(key, () => _AnomalyIdentity(key, weekly: false))
            .add(date, txn);
      }
    }

    final currentKeys = <String>{};
    final retainedInsights = <String>{};
    var alertCount = 0;
    await _database.transaction(() async {
      for (final entry in groups.entries) {
        final key = entry.key;
        final identity = entry.value;
        final currentPeriod = identity.weekly ? currentWeek : currentMonth;
        final currentPeriodToDate =
            calendar.throughToday(currentPeriod, instant);
        final currentStart = currentPeriod.start;
        final periodLimit =
            identity.weekly ? weeklyBaselinePeriods : monthlyBaselinePeriods;
        final firstPeriod = _periodFor(
          identity.firstActivity,
          weekly: identity.weekly,
          calendar: calendar,
        );
        final completedPeriods = _completedStarts(
          firstPeriod.start,
          currentStart,
          limit: periodLimit,
          weekly: identity.weekly,
          calendar: calendar,
        );
        final starts = completedPeriods.starts;
        final periodTotals = <DateTime, double>{};
        for (final txn in identity.transactions) {
          final txnDate = DateTime.fromMillisecondsSinceEpoch(
            txn.ts,
            isUtc: true,
          );
          final start = _periodFor(
            txnDate,
            weekly: identity.weekly,
            calendar: calendar,
          ).start;
          periodTotals.update(
            start,
            (value) => value + txn.amount,
            ifAbsent: () => txn.amount,
          );
        }
        final completedValues = [
          for (final start in starts) periodTotals[start] ?? 0.0,
        ];
        final mean = completedValues.isEmpty
            ? 0.0
            : completedValues.reduce((a, b) => a + b) / completedValues.length;
        final variance = completedValues.isEmpty
            ? 0.0
            : completedValues
                    .map((value) => math.pow(value - mean, 2))
                    .reduce((a, b) => a + b) /
                completedValues.length;
        final std = math.sqrt(variance);
        currentKeys.add(key);
        await _database.into(_database.baselines).insertOnConflictUpdate(
              BaselinesCompanion.insert(
                key: key,
                mean: mean,
                std: std,
                n: completedValues.length,
                updatedAt: starts.isEmpty ? currentStart : starts.last,
              ),
            );

        final currentTransactions = identity.transactions.where((txn) {
          final date = DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true);
          return !date.isBefore(currentPeriod.start) &&
              date.isBefore(currentPeriodToDate.end);
        }).toList();
        if (currentTransactions.isEmpty) continue;
        final aggregate = currentTransactions.fold<double>(
          0,
          (sum, txn) => sum + txn.amount,
        );
        final first = currentTransactions.first;
        final threshold = mean + flags.anomalyAlertSigma * std;
        final periodKey = identity.weekly
            ? _dateKey(calendar.localDate(currentStart))
            : calendar.monthKey(instant);
        final insightId = 'anomaly:$key:$periodKey';
        if (completedPeriods.count < flags.anomalyAlertMinPeriods ||
            aggregate <= threshold) {
          await (_database.delete(_database.insights)
                ..where((row) => row.id.equals(insightId)))
              .go();
          continue;
        }

        final isBelowFloor = first.currencyCode == 'INR' &&
            aggregate < flags.anomalyAlertFloorAmount;
        final isRecurring = !identity.weekly &&
            recurringMerchants.contains(
              '${first.merchantId}|${SourceCurrency(code: first.currencyCode, symbol: first.currencySymbol).bucketKey}',
            );
        final suppressed = isBelowFloor || isRecurring;
        final contributors = [...currentTransactions]
          ..sort((a, b) => b.amount.compareTo(a.amount));
        await _database.into(_database.insights).insertOnConflictUpdate(
              InsightsCompanion.insert(
                id: insightId,
                period: periodKey,
                kind: 'anomaly',
                payloadJson: jsonEncode({
                  'baseline_key': key,
                  'aggregate': aggregate,
                  'currency_code': first.currencyCode,
                  'currency_symbol': first.currencySymbol,
                  'threshold': threshold,
                  'top_transaction_ids': [
                    for (final txn in contributors.take(3)) txn.id,
                  ],
                  'suppressed': suppressed,
                  'suppression_reason': isBelowFloor
                      ? 'below_floor'
                      : (isRecurring ? 'recurring_series' : null),
                }),
              ),
            );
        retainedInsights.add(insightId);
        if (!suppressed) alertCount++;
      }

      final oldBaselines = await (_database.select(_database.baselines)
            ..where((row) => row.key.like('cat:%') | row.key.like('mer:%')))
          .get();
      for (final row in oldBaselines) {
        if (!currentKeys.contains(row.key)) {
          await (_database.delete(_database.baselines)
                ..where((entry) => entry.key.equals(row.key)))
              .go();
        }
      }

      final anomalyRows = await (_database.select(_database.insights)
            ..where((row) => row.kind.equals('anomaly')))
          .get();
      final eligibleIds = transactions.map((row) => row.id).toSet();
      final currentPeriodKeys = {
        _dateKey(calendar.localDate(currentWeek.start)),
        calendar.monthKey(instant),
      };
      for (final row in anomalyRows) {
        var stale = currentPeriodKeys.contains(row.period) &&
            !retainedInsights.contains(row.id);
        try {
          final payload = jsonDecode(row.payloadJson);
          if (payload is Map && payload['top_transaction_ids'] is List) {
            final ids =
                (payload['top_transaction_ids'] as List).whereType<String>();
            stale = stale || ids.any((id) => !eligibleIds.contains(id));
          }
        } on FormatException {
          stale = true;
        }
        if (stale && !retainedInsights.contains(row.id)) {
          await (_database.delete(_database.insights)
                ..where((entry) => entry.id.equals(row.id)))
              .go();
        }
      }
    });
    return alertCount;
  }

  ({List<DateTime> starts, int count}) _completedStarts(
    DateTime firstStart,
    DateTime currentStart, {
    required int limit,
    required bool weekly,
    required FinancialCalendar calendar,
  }) {
    var cursor = firstStart;
    final all = <DateTime>[];
    while (cursor.isBefore(currentStart)) {
      all.add(cursor);
      cursor = weekly
          ? cursor.add(const Duration(days: 7))
          : _nextMonth(cursor, calendar);
    }
    return (
      starts: all.length <= limit ? all : all.sublist(all.length - limit),
      count: all.length,
    );
  }

  FinancialPeriod _periodFor(
    DateTime instant, {
    required bool weekly,
    required FinancialCalendar calendar,
  }) {
    if (!weekly) return calendar.monthContaining(instant);
    return _weekContaining(calendar.localDate(instant), calendar);
  }

  FinancialPeriod _weekContaining(
    DateTime localDate,
    FinancialCalendar calendar,
  ) {
    final date = DateTime.utc(localDate.year, localDate.month, localDate.day);
    final monday =
        date.subtract(Duration(days: date.weekday - DateTime.monday));
    final next = monday.add(const Duration(days: 7));
    return FinancialPeriod(
      start: monday.subtract(calendar.timeZoneOffset),
      end: next.subtract(calendar.timeZoneOffset),
    );
  }

  DateTime _nextMonth(DateTime start, FinancialCalendar calendar) {
    final local = calendar.localDate(start);
    return calendar.month(local.year, local.month + 1).start;
  }

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _AnomalyIdentity {
  _AnomalyIdentity(this.key, {required this.weekly});

  final String key;
  final bool weekly;
  final List<Transaction> transactions = [];
  DateTime? _firstActivity;

  DateTime get firstActivity => _firstActivity!;

  void add(DateTime date, Transaction txn) {
    transactions.add(txn);
    if (_firstActivity == null || date.isBefore(_firstActivity!)) {
      _firstActivity = date;
    }
  }
}
