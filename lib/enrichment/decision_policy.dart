import '../core/constants.dart';

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
  });

  final double merchantConfidence;
  final double categoryConfidence;
  final double amount;
  final int merchantTxnCount;
  final int askBudgetLeft;
  final String? counterpartyVpa;
  final bool counterpartySeen;
}

class DecisionPolicy {
  const DecisionPolicy();

  DecisionStatus decide(DecisionPolicyInput input) {
    final confidence = _min(
      input.merchantConfidence,
      input.categoryConfidence,
    );

    if (input.counterpartyVpa != null &&
        input.counterpartyVpa!.isNotEmpty &&
        !input.counterpartySeen) {
      return input.askBudgetLeft > 0
          ? DecisionStatus.asked
          : DecisionStatus.needsReview;
    }

    if (confidence >= AppConstants.silentConfidenceThreshold) {
      return DecisionStatus.auto;
    }

    final askEligible = confidence >= AppConstants.askConfidenceThreshold &&
        (input.amount >= 500 || input.merchantTxnCount >= 3);
    if (askEligible && input.askBudgetLeft > 0) {
      return DecisionStatus.asked;
    }

    return DecisionStatus.needsReview;
  }

  double _min(double a, double b) => a < b ? a : b;
}
