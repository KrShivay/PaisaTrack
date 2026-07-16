import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../data/db/database.dart';

/// One detected recurring stream written to `recurring_series`.
class RecurringDetection {
  const RecurringDetection({
    required this.id,
    required this.merchantId,
    required this.label,
    required this.expectedAmount,
    required this.period,
    required this.periodDays,
    required this.nextExpectedDate,
    required this.lastAmount,
    required this.amountTrend,
    required this.occurrences,
    required this.status,
    required this.kind,
  });

  final String id;
  final String merchantId;
  final String label;
  final double expectedAmount;
  final String period;
  final int periodDays;
  final DateTime nextExpectedDate;
  final double lastAmount;
  final String amountTrend;
  final int occurrences;
  final String status;
  final String kind;
}

/// Nightly deterministic recurring-series scanner (PLAN §7.6).
class RecurringDetector {
  const RecurringDetector(this._database);

  static const amountTolerancePct = 0.05;
  static const maxGapCoefficientOfVariation = 0.25;
  static const missedGraceFraction = 0.20;

  final AppDatabase _database;

  /// Detects and upserts every qualifying merchant/amount stream atomically.
  Future<List<RecurringDetection>> run({DateTime? today}) {
    final scanDate = (today ?? DateTime.now()).toUtc();
    return _database.transaction(() async {
      final transactions = await (_database.select(_database.transactions)
            ..where(
              (t) =>
                  t.merchantId.isNotNull() &
                  t.isAnalyticsExcluded.equals(false) &
                  t.ownedTransferId.isNull() &
                  t.isDeleted.equals(false) &
                  t.duplicateOfTxnId.isNull(),
            ))
          .get();
      final merchants = {
        for (final merchant
            in await _database.select(_database.merchants).get())
          merchant.id: merchant,
      };
      final grouped = <String, List<_TransactionPoint>>{};
      for (final txn in transactions) {
        final merchantId = txn.merchantId;
        if (merchantId == null) continue;
        grouped.putIfAbsent('$merchantId\u0000${txn.direction}', () => []).add(
              _TransactionPoint(
                id: txn.id,
                merchantId: merchantId,
                direction: txn.direction,
                amount: txn.amount,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  txn.ts,
                  isUtc: true,
                ),
              ),
            );
      }

      final detections = <RecurringDetection>[];
      for (final points in grouped.values) {
        for (final cluster in _amountClusters(points)) {
          final detection = _detectCluster(
            cluster,
            label: merchants[cluster.first.merchantId]?.userLabel ??
                merchants[cluster.first.merchantId]?.canonicalName ??
                cluster.first.merchantId,
            today: scanDate,
          );
          if (detection == null) continue;
          detections.add(detection);
          await _database
              .into(_database.recurringSeries)
              .insertOnConflictUpdate(
                RecurringSeriesCompanion.insert(
                  id: detection.id,
                  merchantId: detection.merchantId,
                  label: detection.label,
                  expectedAmount: detection.expectedAmount,
                  tolerancePct: amountTolerancePct,
                  period: detection.period,
                  periodDays: detection.periodDays,
                  nextExpectedDate: detection.nextExpectedDate,
                  lastAmount: detection.lastAmount,
                  amountTrend: detection.amountTrend,
                  occurrences: detection.occurrences,
                  status: detection.status,
                  kind: detection.kind,
                ),
              );
        }
      }
      return detections;
    });
  }

  List<List<_TransactionPoint>> _amountClusters(
    List<_TransactionPoint> points,
  ) {
    final sorted = [...points]..sort((a, b) => a.amount.compareTo(b.amount));
    final clusters = <List<_TransactionPoint>>[];
    for (final point in sorted) {
      List<_TransactionPoint>? target;
      for (final cluster in clusters) {
        final mean = cluster.fold<double>(0, (sum, item) => sum + item.amount) /
            cluster.length;
        if ((point.amount - mean).abs() / mean <= amountTolerancePct) {
          target = cluster;
          break;
        }
      }
      (target ?? (clusters..add(<_TransactionPoint>[])).last).add(point);
    }
    return clusters;
  }

  RecurringDetection? _detectCluster(
    List<_TransactionPoint> points, {
    required String label,
    required DateTime today,
  }) {
    if (points.length < 3) return null;
    final ordered = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final gaps = <double>[
      for (var i = 1; i < ordered.length; i++)
        ordered[i].timestamp.difference(ordered[i - 1].timestamp).inMinutes /
            Duration.minutesPerDay,
    ];
    final medianGap = _median(gaps);
    final band = _periodBand(medianGap);
    if (band == null ||
        _coefficientOfVariation(gaps) >= maxGapCoefficientOfVariation) {
      return null;
    }

    final periodDays = medianGap.round();
    final last = ordered.last;
    final nextExpected = last.timestamp.add(
      Duration(minutes: (medianGap * Duration.minutesPerDay).round()),
    );
    final grace = Duration(
      minutes:
          (medianGap * Duration.minutesPerDay * missedGraceFraction).round(),
    );
    final amounts = ordered.map((point) => point.amount).toList();
    final lastThree = amounts.skip(math.max(0, amounts.length - 3)).toList();
    final rising = lastThree.length == 3 &&
        lastThree[0] < lastThree[1] &&
        lastThree[1] < lastThree[2];
    final expectedAmount =
        amounts.fold<double>(0, (sum, amount) => sum + amount) / amounts.length;

    return RecurringDetection(
      id: 'rec:${last.merchantId}:${last.direction}:${ordered.first.id}',
      merchantId: last.merchantId,
      label: label,
      expectedAmount: expectedAmount,
      period: band,
      periodDays: periodDays,
      nextExpectedDate: nextExpected,
      lastAmount: last.amount,
      amountTrend: rising ? 'rising' : 'flat',
      occurrences: ordered.length,
      status: today.isAfter(nextExpected.add(grace)) ? 'missed' : 'active',
      kind: _kind(label, last.direction),
    );
  }

  String _kind(String label, String direction) {
    if (direction == 'credit') return 'income';
    final normalized = label.toLowerCase();
    if (normalized.contains('emi') ||
        normalized.contains('loan') ||
        normalized.contains('mortgage')) {
      return 'emi';
    }
    if (normalized.contains('bill') ||
        normalized.contains('electric') ||
        normalized.contains('water') ||
        normalized.contains('gas')) {
      return 'bill';
    }
    return 'subscription';
  }

  String? _periodBand(double days) {
    if (days >= 6 && days <= 8) return 'weekly';
    if (days >= 26 && days <= 35) return 'monthly';
    if (days >= 80 && days <= 100) return 'quarterly';
    if (days >= 350 && days <= 380) return 'yearly';
    return null;
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _coefficientOfVariation(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    if (mean == 0) return double.infinity;
    final variance = values.fold<double>(
          0,
          (sum, value) => sum + math.pow(value - mean, 2),
        ) /
        values.length;
    return math.sqrt(variance) / mean;
  }
}

class _TransactionPoint {
  const _TransactionPoint({
    required this.id,
    required this.merchantId,
    required this.direction,
    required this.amount,
    required this.timestamp,
  });

  final String id;
  final String merchantId;
  final String direction;
  final double amount;
  final DateTime timestamp;
}
