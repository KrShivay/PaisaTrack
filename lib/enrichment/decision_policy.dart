import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../data/db/database.dart';
import 'trusted_category_outcome.dart';

enum DecisionStatus {
  auto('auto'),
  asked('asked'),
  needsReview('needs_review');

  const DecisionStatus(this.wireName);

  final String wireName;
}

class DecisionPolicyInput {
  const DecisionPolicyInput({
    required this.merchantConfidence,
    required this.categoryConfidence,
    required this.amount,
    required this.merchantTxnCount,
    required this.askBudgetLeft,
    this.counterpartyVpa,
    this.counterpartySeen = true,
    this.silentThreshold,
  });

  final double merchantConfidence;
  final double categoryConfidence;
  final double amount;
  final int merchantTxnCount;
  final int askBudgetLeft;
  final String? counterpartyVpa;
  final bool counterpartySeen;
  final double? silentThreshold;
}

class DecisionPolicy {
  const DecisionPolicy();

  DecisionStatus decide(DecisionPolicyInput input) {
    final confidence = _min(
      input.merchantConfidence,
      input.categoryConfidence,
    );

    if (input.counterpartyVpa != null && input.counterpartyVpa!.isNotEmpty) {
      if (!input.counterpartySeen) {
        return input.askBudgetLeft > 0
            ? DecisionStatus.asked
            : DecisionStatus.needsReview;
      }
    }

    if (confidence >=
        (input.silentThreshold ?? AppConstants.silentConfidenceThreshold)) {
      return DecisionStatus.auto;
    }

    final askEligible = confidence >= AppConstants.askConfidenceThreshold &&
        (input.amount >= AppConstants.askAmountThreshold ||
            input.merchantTxnCount >= AppConstants.askMerchantTxnCount);
    if (askEligible && input.askBudgetLeft > 0) {
      return DecisionStatus.asked;
    }

    return DecisionStatus.needsReview;
  }

  double _min(double a, double b) => a < b ? a : b;
}

/// Persists per-category silent thresholds from explicit category outcomes.
/// Unreviewed automatic labels are not evidence. Missing history intentionally
/// returns the static P2 default.
class AdaptiveThresholdPolicy {
  AdaptiveThresholdPolicy(this._database);
  final AppDatabase _database;
  static const _key = 'category_silent_thresholds_v3';
  static const _windowCountsKey = 'category_threshold_window_counts_v3';
  static const _fingerprintsKey = 'category_threshold_evidence_fingerprints_v3';

  Future<double> thresholdFor(String? categoryId) async {
    if (categoryId == null) return AppConstants.silentConfidenceThreshold;
    final row = await (_database.select(_database.modelMeta)
          ..where((m) => m.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return AppConstants.silentConfidenceThreshold;
    try {
      final values = jsonDecode(row.value) as Map<String, Object?>;
      return (values[categoryId] as num?)?.toDouble() ??
          AppConstants.silentConfidenceThreshold;
    } on FormatException {
      return AppConstants.silentConfidenceThreshold;
    } on TypeError {
      return AppConstants.silentConfidenceThreshold;
    }
  }

  Future<Map<String, double>> recompute() async {
    final transactions = await (_database.select(_database.transactions)
          ..where(
            (t) => t.categoryId.isNotNull() & t.isNotTransaction.equals(false),
          ))
        .get();
    final feedback = await (_database.select(_database.feedback)
          ..where((f) => f.field.isIn(['category_id', 'status'])))
        .get();
    final categoryFeedbackByTxn = <String, List<FeedbackData>>{};
    final statusFeedbackByTxn = <String, List<FeedbackData>>{};
    for (final row in feedback) {
      if (row.context.trim().isEmpty) continue;
      final target = row.field == 'category_id'
          ? categoryFeedbackByTxn
          : statusFeedbackByTxn;
      target.putIfAbsent(row.txnId, () => []).add(row);
    }
    int byTimeThenId(FeedbackData a, FeedbackData b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    }

    for (final rows in categoryFeedbackByTxn.values) {
      rows.sort(byTimeThenId);
    }
    for (final rows in statusFeedbackByTxn.values) {
      rows.sort(byTimeThenId);
    }

    final events = <({
      String transactionId,
      String category,
      DateTime at,
      bool corrected
    })>[];
    const explicitConfirmationContexts = {'activity_confirm', 'sort_confirm'};
    for (final transaction in transactions) {
      if (transaction.parseSource == 'manual' ||
          !hasCategoryPredictionEvidence(transaction.confidenceJson)) {
        continue;
      }

      final corrections = categoryFeedbackByTxn[transaction.id];
      final statusFeedback = statusFeedbackByTxn[transaction.id];
      final latestStatus = statusFeedback == null || statusFeedback.isEmpty
          ? null
          : statusFeedback.last;
      if (corrections != null && corrections.isNotEmpty) {
        final originalCategory = corrections.first.oldValue;
        if (originalCategory != null) {
          events.add(
            (
              transactionId: transaction.id,
              category: originalCategory,
              at: latestStatus?.newValue == 'confirmed' &&
                      explicitConfirmationContexts
                          .contains(latestStatus?.context)
                  ? latestStatus!.createdAt
                  : corrections.first.createdAt,
              corrected: transaction.categoryId != originalCategory,
            ),
          );
        }
        continue;
      }

      if (transaction.status == 'confirmed' &&
          latestStatus?.newValue == 'confirmed' &&
          explicitConfirmationContexts.contains(latestStatus?.context)) {
        events.add(
          (
            transactionId: transaction.id,
            category: transaction.categoryId!,
            at: latestStatus!.createdAt,
            corrected: false
          ),
        );
      }
    }
    events.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      return byTime != 0 ? byTime : a.transactionId.compareTo(b.transactionId);
    });
    final thresholds = await _readDoubleMap(_key);
    final processedCounts = await _readIntMap(_windowCountsKey);
    final processedFingerprints = await _readStringMap(_fingerprintsKey);
    final result = <String, double>{};
    final categories = events.map((event) => event.category).toSet()
      ..addAll(thresholds.keys)
      ..addAll(processedCounts.keys)
      ..addAll(processedFingerprints.keys);
    final clearedCategories = <String>{};
    var stateChanged = false;
    for (final category in categories) {
      final categoryEvents =
          events.where((event) => event.category == category).toList();
      final completeCount = categoryEvents.length ~/ 50 * 50;
      if (completeCount == 0) {
        if (thresholds.containsKey(category) ||
            processedCounts.containsKey(category) ||
            processedFingerprints.containsKey(category)) {
          clearedCategories.add(category);
          result[category] = AppConstants.silentConfidenceThreshold;
          stateChanged = true;
        }
        continue;
      }
      final completedEvents = categoryEvents.take(completeCount).toList();
      final fingerprintSink = Sha256().newHashSink();
      for (final event in completedEvents) {
        fingerprintSink.add(
          utf8.encode(
            '${jsonEncode([
                  event.transactionId,
                  event.category,
                  event.at.millisecondsSinceEpoch,
                  event.corrected,
                ])}\n',
          ),
        );
      }
      fingerprintSink.close();
      final fingerprint =
          base64Url.encode((await fingerprintSink.hash()).bytes);
      if (processedCounts[category] == completeCount &&
          processedFingerprints[category] == fingerprint) {
        continue;
      }

      var recomputed = AppConstants.silentConfidenceThreshold;
      for (var start = 0; start < completeCount; start += 50) {
        final window = completedEvents.skip(start).take(50);
        final errors = window.where((event) => event.corrected).length;
        recomputed = errors / 50 > .15
            ? (recomputed + .03).clamp(0.0, .98)
            : (recomputed - .01).clamp(0.0, .98);
      }
      result[category] = recomputed;
      processedCounts[category] = completeCount;
      processedFingerprints[category] = fingerprint;
      stateChanged = true;
    }
    if (stateChanged) {
      for (final category in clearedCategories) {
        thresholds.remove(category);
        processedCounts.remove(category);
        processedFingerprints.remove(category);
      }
      for (final entry in result.entries) {
        if (!clearedCategories.contains(entry.key)) {
          thresholds[entry.key] = entry.value;
        }
      }
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(key: _key, value: jsonEncode(thresholds)),
          );
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: _windowCountsKey,
              value: jsonEncode(processedCounts),
            ),
          );
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: _fingerprintsKey,
              value: jsonEncode(processedFingerprints),
            ),
          );
    }
    return result;
  }

  Future<Map<String, double>> _readDoubleMap(String key) async {
    final row = await (_database.select(_database.modelMeta)
          ..where((m) => m.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return {};
    try {
      final decoded = jsonDecode(row.value) as Map<String, Object?>;
      return decoded
          .map((key, value) => MapEntry(key, (value as num).toDouble()));
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<Map<String, int>> _readIntMap(String key) async {
    final values = await _readDoubleMap(key);
    return values.map((key, value) => MapEntry(key, value.toInt()));
  }

  Future<Map<String, String>> _readStringMap(String key) async {
    final row = await (_database.select(_database.modelMeta)
          ..where((m) => m.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return {};
    try {
      final decoded = jsonDecode(row.value) as Map<String, Object?>;
      return decoded.map((key, value) => MapEntry(key, value as String));
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }
}
