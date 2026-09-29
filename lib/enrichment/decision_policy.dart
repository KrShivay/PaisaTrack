import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../data/db/database.dart';

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
  static const _key = 'category_silent_thresholds_v2';
  static const _windowCountsKey = 'category_threshold_window_counts_v2';

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
    bool hasCategoryPredictionEvidence(String confidenceJson) {
      try {
        final payload = jsonDecode(confidenceJson) as Map<String, Object?>;
        final category = payload['category'] as Map<String, Object?>?;
        return category?['c'] is num && category?['src'] is String;
      } on FormatException {
        return false;
      } on TypeError {
        return false;
      }
    }

    const explicitConfirmationContexts = {'activity_confirm', 'sort_confirm'};
    for (final transaction in transactions) {
      if (transaction.parseSource == 'manual' ||
          !hasCategoryPredictionEvidence(transaction.confidenceJson)) {
        continue;
      }

      final corrections = categoryFeedbackByTxn[transaction.id];
      if (corrections != null && corrections.isNotEmpty) {
        final originalCategory = corrections.first.oldValue;
        if (originalCategory != null) {
          events.add(
            (
              transactionId: transaction.id,
              category: originalCategory,
              at: corrections.last.createdAt,
              corrected: transaction.categoryId != originalCategory,
            ),
          );
        }
        continue;
      }

      final statusFeedback = statusFeedbackByTxn[transaction.id];
      final latestStatus = statusFeedback == null || statusFeedback.isEmpty
          ? null
          : statusFeedback.last;
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
      final byTime = b.at.compareTo(a.at);
      return byTime != 0 ? byTime : a.transactionId.compareTo(b.transactionId);
    });
    final thresholds = await _readDoubleMap(_key);
    final processedCounts = await _readIntMap(_windowCountsKey);
    final result = <String, double>{};
    for (final category in events.map((event) => event.category).toSet()) {
      final categoryEvents =
          events.where((event) => event.category == category).toList();
      final previousCount = processedCounts[category] ?? 0;
      if (categoryEvents.length - previousCount < 50) continue;
      final recent = categoryEvents.take(50).toList();
      final errors = recent.where((event) => event.corrected).length;
      final current =
          thresholds[category] ?? AppConstants.silentConfidenceThreshold;
      result[category] = errors / recent.length > .15
          ? (current + .03).clamp(0.0, .98)
          : (current - .01).clamp(0.0, .98);
      processedCounts[category] = categoryEvents.length;
    }
    if (result.isNotEmpty) {
      thresholds.addAll(result);
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(key: _key, value: jsonEncode(thresholds)),
          );
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: _windowCountsKey,
              value: jsonEncode(processedCounts),
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
}
