import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/event_correlator.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';

void main() {
  const correlator = EventCorrelator();
  final baseTs = DateTime.utc(2026, 7, 10, 12, 0);

  test('auto-links full refund on exact ref ID within 30 days', () {
    final refund = NormalizedTransactionRecord(
      amount: 450.0,
      direction: TransactionDirection.credit,
      channel: TransactionChannel.upi,
      merchantRaw: 'Swiggy',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: 'RRN99887766',
      ts: baseTs.add(const Duration(days: 2)),
      parseSource: ParseSource.generic,
      parseConfidence: 0.9,
    );

    final expense = Transaction(
      id: 'txn_expense_1',
      ts: baseTs.millisecondsSinceEpoch,
      amount: 450.0,
      direction: 'debit',
      channel: 'upi',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      refId: 'RRN99887766',
      isDeleted: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: baseTs,
      updatedAt: baseTs,
    );

    final result = correlator.correlateRefund(
      refundRecord: refund,
      candidates: [expense],
    );

    expect(result, isNotNull);
    expect(result!.matchedTransactionId, 'txn_expense_1');
    expect(result.linkType, TransactionLinkType.refunds);
    expect(result.confidence, 0.99);
  });

  test('auto-links partial refund on single candidate matching counterparty and amount <= expense', () {
    final refund = NormalizedTransactionRecord(
      amount: 150.0, // Partial refund of 450
      direction: TransactionDirection.credit,
      channel: TransactionChannel.upi,
      merchantRaw: 'Swiggy',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: baseTs.add(const Duration(days: 3)),
      parseSource: ParseSource.generic,
      parseConfidence: 0.9,
    );

    final expense = Transaction(
      id: 'txn_expense_1',
      ts: baseTs.millisecondsSinceEpoch,
      amount: 450.0,
      direction: 'debit',
      channel: 'upi',
      merchantRaw: 'Swiggy',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      isDeleted: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: baseTs,
      updatedAt: baseTs,
    );

    final result = correlator.correlateRefund(
      refundRecord: refund,
      candidates: [expense],
    );

    expect(result, isNotNull);
    expect(result!.matchedTransactionId, 'txn_expense_1');
    expect(result.linkType, TransactionLinkType.refunds);
    expect(result.confidence, greaterThanOrEqualTo(0.90));
  });

  test('fails closed (unlinked) when multiple ambiguous candidates match', () {
    final refund = NormalizedTransactionRecord(
      amount: 200.0,
      direction: TransactionDirection.credit,
      channel: TransactionChannel.upi,
      merchantRaw: 'Amazon',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: baseTs.add(const Duration(days: 1)),
      parseSource: ParseSource.generic,
      parseConfidence: 0.9,
    );

    final expense1 = Transaction(
      id: 'txn_amazon_1',
      ts: baseTs.millisecondsSinceEpoch,
      amount: 200.0,
      direction: 'debit',
      channel: 'upi',
      merchantRaw: 'Amazon',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      isDeleted: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: baseTs,
      updatedAt: baseTs,
    );

    final expense2 = Transaction(
      id: 'txn_amazon_2',
      ts: baseTs.add(const Duration(hours: 2)).millisecondsSinceEpoch,
      amount: 200.0,
      direction: 'debit',
      channel: 'upi',
      merchantRaw: 'Amazon',
      parseSource: 'generic',
      confidenceJson: '{}',
      status: 'auto',
      isDeleted: false,
      isAnalyticsExcluded: false,
      lifecycleState: 'settled',
      createdAt: baseTs,
      updatedAt: baseTs,
    );

    final result = correlator.correlateRefund(
      refundRecord: refund,
      candidates: [expense1, expense2],
    );

    expect(result, isNull); // Ambiguous -> fails closed unlinked
  });
}
