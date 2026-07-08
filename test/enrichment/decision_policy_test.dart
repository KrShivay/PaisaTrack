import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/enrichment/decision_policy.dart';

void main() {
  const policy = DecisionPolicy();

  DecisionPolicyInput input({
    double merchantConfidence = 0.8,
    double categoryConfidence = 0.8,
    double amount = 499,
    int merchantTxnCount = 0,
    int askBudgetLeft = 2,
    String? counterpartyVpa,
    bool counterpartySeen = true,
  }) {
    return DecisionPolicyInput(
      merchantConfidence: merchantConfidence,
      categoryConfidence: categoryConfidence,
      amount: amount,
      merchantTxnCount: merchantTxnCount,
      askBudgetLeft: askBudgetLeft,
      counterpartyVpa: counterpartyVpa,
      counterpartySeen: counterpartySeen,
    );
  }

  test('table driven status branches', () {
    final cases = [
      (
        name: 'silent high confidence',
        input: input(merchantConfidence: 0.95, categoryConfidence: 0.9),
        status: DecisionStatus.auto,
      ),
      (
        name: 'minimum confidence controls decision',
        input: input(merchantConfidence: 1, categoryConfidence: 0.59),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'medium confidence asks for high amount',
        input: input(amount: 500),
        status: DecisionStatus.asked,
      ),
      (
        name: 'medium confidence asks for familiar merchant',
        input: input(merchantTxnCount: 3),
        status: DecisionStatus.asked,
      ),
      (
        name: 'daily budget exhaustion falls to review',
        input: input(amount: 500, askBudgetLeft: 0),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'medium confidence low amount unfamiliar merchant reviews',
        input: input(amount: 499, merchantTxnCount: 2),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'unseen p2p counterparty asks once',
        input: input(
          merchantConfidence: 0.2,
          categoryConfidence: 0.2,
          counterpartyVpa: 'friend@upi',
          counterpartySeen: false,
        ),
        status: DecisionStatus.asked,
      ),
      (
        name: 'unseen p2p respects exhausted ask budget',
        input: input(
          counterpartyVpa: 'friend@upi',
          counterpartySeen: false,
          askBudgetLeft: 0,
        ),
        status: DecisionStatus.needsReview,
      ),
    ];

    for (final c in cases) {
      expect(policy.decide(c.input), c.status, reason: c.name);
    }
  });

  test('wire names match transaction status values', () {
    expect(DecisionStatus.auto.wireName, 'auto');
    expect(DecisionStatus.asked.wireName, 'asked');
    expect(DecisionStatus.needsReview.wireName, 'needs_review');
  });
}
