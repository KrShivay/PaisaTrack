import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../data/db/database.dart';
import 'models/embedder.dart';

const _foregroundScanCheckpointKey = 'recurring_foreground_scan_checkpoint_v2';

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
  const RecurringDetector(
    this._database, {
    Embedder embedder = const NoopEmbedder(),
  }) : _embedder = embedder;

  static const amountTolerancePct = 0.05;
  static const maxGapCoefficientOfVariation = 0.25;
  static const missedGraceFraction = 0.20;

  final AppDatabase _database;
  final Embedder _embedder;

  /// Detects and upserts every qualifying merchant/amount stream atomically.
  Future<List<RecurringDetection>> run({DateTime? today}) async {
    final scanDate = (today ?? DateTime.now()).toUtc();
    final transactions = await (_database.select(_database.transactions)
          ..where(
            (t) =>
                (t.merchantId.isNotNull() |
                    t.counterpartyVpa.isNotNull() |
                    t.merchantRaw.isNotNull()) &
                t.isAnalyticsExcluded.equals(false) &
                t.ownedTransferId.isNull() &
                t.isDeleted.equals(false) &
                t.duplicateOfTxnId.isNull(),
          ))
        .get();
    final merchants = {
      for (final merchant in await _database.select(_database.merchants).get())
        merchant.id: merchant,
    };
    final categories = {
      for (final category in await _database.select(_database.categories).get())
        category.id: category,
    };
    final semanticKinds = await _semanticKindVectors();
    final knownMerchantIds = merchants.keys.toSet();
    final grouped = <String, List<_TransactionPoint>>{};
    final fallbackLabels = <String, String>{};
    for (final txn in transactions) {
      var merchantId = txn.merchantId;
      if (merchantId == null) {
        final evidence = txn.merchantRaw ?? txn.counterpartyVpa;
        final normalized = _normalizeEvidence(evidence);
        if (normalized == null) continue;
        merchantId = 'merchant_evidence_$normalized';
        fallbackLabels.putIfAbsent(merchantId, () => evidence!.trim());
      }
      grouped.putIfAbsent('$merchantId\u0000${txn.direction}', () => []).add(
            _TransactionPoint(
              id: txn.id,
              merchantId: merchantId,
              direction: txn.direction,
              amount: txn.amount,
              categoryId: txn.categoryId,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                txn.ts,
                isUtc: true,
              ),
            ),
          );
    }

    final detections = <RecurringDetection>[];
    final pendingWrites = <_PendingRecurringWrite>[];
    void stage(RecurringDetection detection, List<_TransactionPoint> points) {
      detections.add(detection);
      pendingWrites.add(
        _PendingRecurringWrite(detection: detection, points: points),
      );
    }

    for (final points in grouped.values) {
      final merchantId = points.first.merchantId;
      final label = merchants[merchantId]?.userLabel ??
          merchants[merchantId]?.canonicalName ??
          fallbackLabels[merchantId] ??
          merchantId;
      final kind = await _kindFor(
        points,
        label: label,
        categories: categories,
        semanticKinds: semanticKinds,
      );
      var detectedStableAmountCluster = false;
      for (final cluster in _amountClusters(points)) {
        final detection = _detectCluster(
          cluster,
          label: label,
          kind: kind,
          today: scanDate,
        );
        if (detection == null) continue;
        detectedStableAmountCluster = true;
        stage(detection, cluster);
      }
      // Utilities and recharges recur on a stable cadence even when usage
      // makes the amount vary. Keep the narrow amount clusters first to
      // separate multiple subscriptions at one merchant, then fall back to
      // cadence-only detection when none of those clusters qualify.
      if (!detectedStableAmountCluster &&
          points.length >= 3 &&
          _supportsVariableAmounts(kind)) {
        final detection = _detectCluster(
          points,
          label: label,
          kind: kind,
          today: scanDate,
        );
        if (detection != null) stage(detection, points);
      }
    }

    // Keep the database transaction limited to persistence. Clustering can be
    // expensive on imported histories and must not starve unrelated reads.
    await _database.transaction(() async {
      for (final write in pendingWrites) {
        final detection = write.detection;
        await _ensureMerchant(
          detection.merchantId,
          detection.label,
          write.points,
          knownMerchantIds: knownMerchantIds,
        );
        await _database.into(_database.recurringSeries).insertOnConflictUpdate(
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
    });
    return detections;
  }

  String? _normalizeEvidence(String? value) {
    final normalized =
        value?.trim().toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<void> _ensureMerchant(
    String merchantId,
    String label,
    List<_TransactionPoint> points, {
    required Set<String> knownMerchantIds,
  }) async {
    if (knownMerchantIds.contains(merchantId)) return;
    final ordered = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _database.into(_database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: merchantId,
            canonicalName: label,
            firstSeen: ordered.first.timestamp,
            lastSeen: ordered.last.timestamp,
          ),
        );
    knownMerchantIds.add(merchantId);
  }

  List<List<_TransactionPoint>> _amountClusters(
    List<_TransactionPoint> points,
  ) {
    final sorted = [...points]..sort((a, b) => a.amount.compareTo(b.amount));
    final clusters = <List<_TransactionPoint>>[];
    var latestSum = 0.0;
    for (final point in sorted) {
      if (clusters.isEmpty) {
        clusters.add([point]);
        latestSum = point.amount;
        continue;
      }
      final latest = clusters.last;
      final mean = latestSum / latest.length;
      if ((point.amount - mean).abs() / mean <= amountTolerancePct) {
        latest.add(point);
        latestSum += point.amount;
      } else {
        clusters.add([point]);
        latestSum = point.amount;
      }
    }
    return clusters;
  }

  RecurringDetection? _detectCluster(
    List<_TransactionPoint> points, {
    required String label,
    required String kind,
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
      kind: kind,
    );
  }

  String? _kind(String label, String direction) {
    if (direction == 'credit') return 'income';
    final normalized = label.toLowerCase();
    if (normalized.contains('ambig') ||
        normalized.contains('unknown') ||
        normalized.contains('unclassified')) {
      return 'unclassified';
    }
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
    if (normalized.contains('recharge') ||
        normalized.contains('prepaid') ||
        normalized.contains('postpaid') ||
        normalized.contains('mobile') ||
        normalized.contains('broadband') ||
        normalized.contains('dth')) {
      return 'recharge';
    }
    if (normalized.contains('mutual') ||
        normalized.contains('fund') ||
        normalized.contains('sip') ||
        normalized.contains('nps') ||
        normalized.contains('pension') ||
        normalized.contains('investment')) {
      return 'investment';
    }
    return null;
  }

  Future<String> _kindFor(
    List<_TransactionPoint> points, {
    required String label,
    required Map<String, Category> categories,
    required Map<String, Float32List> semanticKinds,
  }) async {
    final direction = points.first.direction;
    if (direction == 'credit') return 'income';
    final categoryKind = _kindFromCategories(points, categories);
    if (categoryKind != null) return categoryKind;
    final labelKind = _kind(label, direction);
    if (labelKind != null) return labelKind;
    if (semanticKinds.isNotEmpty) {
      final labelVector = await _embedder.embed(label);
      if (labelVector != null) {
        String? bestKind;
        var bestScore = double.negativeInfinity;
        for (final entry in semanticKinds.entries) {
          final score = _cosineSimilarity(labelVector, entry.value);
          if (score > bestScore) {
            bestKind = entry.key;
            bestScore = score;
          }
        }
        if (bestKind != null && bestScore >= 0.45) return bestKind;
      }
    }
    return 'subscription';
  }

  String? _kindFromCategories(
    List<_TransactionPoint> points,
    Map<String, Category> categories,
  ) {
    final counts = <String, int>{};
    for (final point in points) {
      final category = categories[point.categoryId];
      if (category == null) continue;
      final rootId = category.parentId ?? category.id;
      final kind = switch (rootId) {
        'emi_loans' => 'emi',
        'bills_utilities' when category.id == 'bills_mobile_recharge' =>
          'recharge',
        'bills_utilities' when category.id == 'bills_broadband_wifi' =>
          'recharge',
        'bills_utilities' when category.id == 'bills_dth_tv' => 'recharge',
        'bills_utilities' => 'bill',
        'subscriptions' => 'subscription',
        'investments' => 'investment',
        'income' => 'income',
        'rent_housing' => 'bill',
        _ => null,
      };
      if (kind != null) counts[kind] = (counts[kind] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<Map<String, Float32List>> _semanticKindVectors() async {
    if (!await _embedder.isModelAvailable()) return const {};
    const prompts = <String, String>{
      'emi': 'loan EMI mortgage repayment',
      'bill': 'monthly household utility rent insurance bill',
      'recharge': 'mobile broadband DTH prepaid recharge',
      'investment': 'SIP mutual fund NPS investment contribution',
      'subscription': 'recurring software streaming membership subscription',
    };
    final vectors = <String, Float32List>{};
    for (final entry in prompts.entries) {
      final vector = await _embedder.embed(entry.value);
      if (vector != null) vectors[entry.key] = vector;
    }
    return vectors;
  }

  bool _supportsVariableAmounts(String kind) {
    return kind == 'bill' || kind == 'recharge' || kind == 'investment';
  }

  double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.isEmpty || a.length != b.length) return -1;
    var dot = 0.0;
    var aNorm = 0.0;
    var bNorm = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aNorm += a[i] * a[i];
      bNorm += b[i] * b[i];
    }
    if (aNorm == 0 || bNorm == 0) return -1;
    return dot / (math.sqrt(aNorm) * math.sqrt(bNorm));
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

/// Runs the foreground recurring scan only when transaction data changed.
///
/// The nightly job remains responsible for time-based status refreshes. This
/// checkpoint makes correctness independent of Android background scheduling
/// without adding a full-table scan to every app resume.
class ForegroundRecurringScanner {
  const ForegroundRecurringScanner(
    this._database, {
    Embedder embedder = const NoopEmbedder(),
  }) : _embedder = embedder;

  final AppDatabase _database;
  final Embedder _embedder;

  Future<bool> runIfStale({DateTime? now}) async {
    final startedAt = (now ?? DateTime.now()).toUtc();
    final checkpoint = await (_database.select(_database.modelMeta)
          ..where((row) => row.key.equals(_foregroundScanCheckpointKey)))
        .getSingleOrNull();
    final lastScan = DateTime.tryParse(checkpoint?.value ?? '')?.toUtc();
    if (lastScan != null) {
      final changed = await (_database.select(_database.transactions)
            ..where((row) => row.updatedAt.isBiggerThanValue(lastScan))
            ..limit(1))
          .getSingleOrNull();
      if (changed == null) return false;
    }

    await RecurringDetector(
      _database,
      embedder: _embedder,
    ).run(today: startedAt);
    await _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: _foregroundScanCheckpointKey,
            value: startedAt.toIso8601String(),
          ),
        );
    return true;
  }
}

class _TransactionPoint {
  const _TransactionPoint({
    required this.id,
    required this.merchantId,
    required this.direction,
    required this.amount,
    this.categoryId,
    required this.timestamp,
  });

  final String id;
  final String merchantId;
  final String direction;
  final double amount;
  final String? categoryId;
  final DateTime timestamp;
}

class _PendingRecurringWrite {
  const _PendingRecurringWrite({
    required this.detection,
    required this.points,
  });

  final RecurringDetection detection;
  final List<_TransactionPoint> points;
}

/// Computes the total monthly commitment load across all active recurring detections (T-139a).
double computeTotalMonthlyCommitmentLoad(List<RecurringDetection> detections) {
  var total = 0.0;
  for (final d in detections) {
    if (d.status != 'active' || d.kind == 'income') continue;
    final monthlyAmount = switch (d.period) {
      'weekly' => d.expectedAmount * (365 / 7 / 12),
      'fortnightly' => d.expectedAmount * (365 / 14 / 12),
      'monthly' => d.expectedAmount,
      'quarterly' => d.expectedAmount / 3,
      'yearly' => d.expectedAmount / 12,
      _ => d.expectedAmount,
    };
    total += monthlyAmount;
  }
  return total;
}
