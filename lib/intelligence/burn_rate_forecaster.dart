import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/financial_calendar.dart';
import '../data/analytics/financial_eligibility.dart';
import '../data/db/database.dart';

/// Deterministic month-end spending projection from three trailing months.
class BurnRateForecast {
  const BurnRateForecast({
    required this.period,
    required this.asOfDay,
    required this.currentSpend,
    required this.projectedSpend,
    required this.trailingAverage,
    required this.remainingMedianSpend,
    required this.deviationFraction,
    required this.insightEmitted,
  });

  final String period;
  final int asOfDay;
  final double currentSpend;
  final double projectedSpend;
  final double trailingAverage;
  final double remainingMedianSpend;
  final double deviationFraction;
  final bool insightEmitted;
}

/// Computes PLAN §7.8 burn rate and persists material deviations as insights.
class BurnRateForecaster {
  const BurnRateForecaster(this._database, {FinancialCalendar? calendar})
      : _calendar = calendar;

  static const trailingMonths = 3;
  static const insightDeviationThreshold = 0.10;

  final AppDatabase _database;
  final FinancialCalendar? _calendar;

  /// Forecasts the local calendar month containing [today].
  ///
  /// Historical daily medians use only months in which that calendar day
  /// exists, so a missing February 30/31 is not mistaken for zero spending.
  Future<BurnRateForecast> run({DateTime? today}) {
    final calendar = _calendar ?? FinancialCalendar();
    final now = calendar.localDate(today ?? DateTime.now());
    return _database.transaction(() async {
      final currentPeriod = calendar.monthContaining(today ?? DateTime.now());
      final nextMonth = currentPeriod.end;
      final historyStart = DateTime.utc(now.year, now.month - trailingMonths)
          .subtract(calendar.timeZoneOffset);
      final rows = await (_database.select(_database.transactions)
            ..where(
              (t) =>
                  t.ts.isBiggerOrEqualValue(
                    historyStart.millisecondsSinceEpoch,
                  ) &
                  t.ts.isSmallerThanValue(nextMonth.millisecondsSinceEpoch) &
                  t.isAnalyticsExcluded.equals(false) &
                  t.ownedTransferId.isNull() &
                  t.isDeleted.equals(false) &
                  t.duplicateOfTxnId.isNull() &
                  t.lifecycleState.equals('settled') &
                  t.direction.equals('debit'),
            ))
          .get();

      final categoryIsSpending = {
        for (final category
            in await _database.select(_database.categories).get())
          category.id: category.isSpending,
      };
      final eligible = rows
          .where(
            (transaction) => FinancialEligibility.includesSpendingDebit(
              transaction,
              categoryIsSpending:
                  categoryIsSpending[transaction.categoryId] ?? true,
            ),
          )
          .toList(growable: false);

      final dailySpend = <String, double>{};
      for (final transaction in eligible) {
        final date = calendar.localDate(
          DateTime.fromMillisecondsSinceEpoch(transaction.ts, isUtc: true),
        );
        final key = _dateKey(date);
        dailySpend[key] = (dailySpend[key] ?? 0) + transaction.amount;
      }

      final currentSpend = eligible.fold<double>(0, (sum, transaction) {
        final instant = DateTime.fromMillisecondsSinceEpoch(
          transaction.ts,
          isUtc: true,
        );
        return currentPeriod.contains(instant) &&
                calendar.localDate(instant).day <= now.day
            ? sum + transaction.amount
            : sum;
      });
      final historyMonths = <DateTime>[
        for (var offset = trailingMonths; offset >= 1; offset--)
          DateTime.utc(now.year, now.month - offset),
      ];
      final historicalTotals = <double>[
        for (final month in historyMonths) _monthTotal(month, dailySpend),
      ];
      final trailingAverage =
          historicalTotals.reduce((a, b) => a + b) / trailingMonths;

      var remainingMedianSpend = 0.0;
      final lastCurrentDay = DateTime.utc(now.year, now.month + 1, 0).day;
      for (var day = now.day + 1; day <= lastCurrentDay; day++) {
        final samples = <double>[];
        for (final month in historyMonths) {
          if (day <= _daysInMonth(month)) {
            samples.add(dailySpend[_dayKey(month, day)] ?? 0);
          }
        }
        remainingMedianSpend += _median(samples);
      }

      final projectedSpend = currentSpend + remainingMedianSpend;
      final deviationFraction = trailingAverage == 0
          ? 0.0
          : (projectedSpend - trailingAverage) / trailingAverage;
      final insightEmitted =
          deviationFraction.abs() > insightDeviationThreshold;
      final period = calendar.monthKey(today ?? DateTime.now());
      final insightId = 'forecast:$period';
      if (insightEmitted) {
        await _database.into(_database.insights).insertOnConflictUpdate(
              InsightsCompanion.insert(
                id: insightId,
                period: period,
                kind: 'forecast',
                payloadJson: jsonEncode({
                  'as_of_day': now.day,
                  'current_spend': currentSpend,
                  'remaining_median_spend': remainingMedianSpend,
                  'projected_spend': projectedSpend,
                  'trailing_three_month_average': trailingAverage,
                  'deviation_fraction': deviationFraction,
                }),
              ),
            );
      } else {
        await (_database.delete(_database.insights)
              ..where((i) => i.id.equals(insightId)))
            .go();
      }

      return BurnRateForecast(
        period: period,
        asOfDay: now.day,
        currentSpend: currentSpend,
        projectedSpend: projectedSpend,
        trailingAverage: trailingAverage,
        remainingMedianSpend: remainingMedianSpend,
        deviationFraction: deviationFraction,
        insightEmitted: insightEmitted,
      );
    });
  }

  double _monthTotal(DateTime month, Map<String, double> dailySpend) {
    var total = 0.0;
    for (var day = 1; day <= _daysInMonth(month); day++) {
      total += dailySpend[_dayKey(month, day)] ?? 0;
    }
    return total;
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  int _daysInMonth(DateTime month) => DateTime.utc(month.year, month.month + 1)
      .subtract(const Duration(days: 1))
      .day;

  String _dateKey(DateTime date) => _dayKey(date, date.day);

  String _dayKey(DateTime month, int day) =>
      '${_monthKey(month)}-${day.toString().padLeft(2, '0')}';

  String _monthKey(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
}
