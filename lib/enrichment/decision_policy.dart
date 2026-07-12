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
      return DecisionStatus.needsReview;
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

/// Persists per-category silent thresholds and adapts them from the last 50
/// automatic labels. Missing history intentionally returns the P2 default.
class AdaptiveThresholdPolicy {
  AdaptiveThresholdPolicy(this._database);
  final AppDatabase _database;
  static const _key = 'category_silent_thresholds_v1';

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
            (t) =>
                t.status.equals(DecisionStatus.auto.wireName) &
                t.categoryId.isNotNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final feedback = await _database.select(_database.feedback).get();
    final corrected = feedback
        .where((f) => f.field == 'category_id')
        .map((f) => f.txnId)
        .toSet();
    final result = <String, double>{};
    for (final category in transactions.map((t) => t.categoryId!).toSet()) {
      final recent =
          transactions.where((t) => t.categoryId == category).take(50).toList();
      if (recent.length < 50) continue;
      final errors = recent.where((t) => corrected.contains(t.id)).length;
      final current = await thresholdFor(category);
      result[category] = errors / recent.length > .15
          ? (current + .03).clamp(0.0, .98)
          : (current - .01).clamp(0.0, .98);
    }
    if (result.isNotEmpty) {
      await _database.into(_database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(key: _key, value: jsonEncode(result)),
          );
    }
    return result;
  }
}
