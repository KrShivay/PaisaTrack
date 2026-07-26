import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/event_correlator.dart';
import 'package:paisatrack/data/dedup/duplicate_match_rule.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  late EventCorrelator correlator;

  setUp(() {
    correlator = const EventCorrelator();
  });

  group('EventCorrelator', () {
    test('normalizes UTR / ref IDs correctly', () {
      expect(EventCorrelator.normalizeRefId('616016648401'), '616016648401');
      expect(EventCorrelator.normalizeRefId('Ref# 616016648401/UPI'), '616016648401');
      expect(EventCorrelator.normalizeRefId('123'), null);
      expect(EventCorrelator.normalizeRefId('ABCDEF'), 'ABCDEF');
    });

    test('ref disagreement vetoes correlation and matching', () {
      expect(EventCorrelator.hasRefDisagreement('616016648401', '616016648402'), isTrue);
      expect(EventCorrelator.hasRefDisagreement('616016648401', '616016648401'), isFalse);
      expect(EventCorrelator.hasRefDisagreement('616016648401', null), isFalse);

      const rule = DuplicateMatchRule(
        window: Duration(minutes: 10),
        amountTolerance: 0.01,
      );

      final txn = Transaction(
        id: 'txn_existing',
        ts: DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch,
        amount: 500.0,
        direction: 'debit',
        channel: 'upi',
        parseSource: 'generic',
        confidenceJson: '{}',
        status: 'auto',
        isDeleted: false,
        isAnalyticsExcluded: false,
        lifecycleState: 'settled',
        refId: '616016648401',
        createdAt: DateTime.utc(2026, 7, 10),
        updatedAt: DateTime.utc(2026, 7, 10),
      );

      // Same amount, same time, but different ref id -> VETO (returns false)
      final matches = rule.matches(
        direction: 'debit',
        amount: 500.0,
        ts: DateTime.utc(2026, 7, 10, 10, 1),
        refId: '616016648402',
        counterpartyKey: null,
        existing: txn,
      );

      expect(matches, isFalse);
    });

    test('AMAZON does not match AMAZONPAYLATER', () {
      const rule = DuplicateMatchRule(
        window: Duration(minutes: 10),
        amountTolerance: 0.01,
      );

      final txn = Transaction(
        id: 'txn_existing',
        ts: DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch,
        amount: 500.0,
        direction: 'debit',
        channel: 'upi',
        parseSource: 'generic',
        confidenceJson: '{}',
        status: 'auto',
        isDeleted: false,
        isAnalyticsExcluded: false,
        lifecycleState: 'settled',
        merchantRaw: 'AMAZON',
        createdAt: DateTime.utc(2026, 7, 10),
        updatedAt: DateTime.utc(2026, 7, 10),
      );

      final matches = rule.matches(
        direction: 'debit',
        amount: 500.0,
        ts: DateTime.utc(2026, 7, 10, 10, 1),
        refId: null,
        counterpartyKey: 'AMAZONPAYLATER',
        existing: txn,
      );

      expect(matches, isFalse);
    });

    test('correlates auth and settlement across days', () {
      final record = NormalizedTransactionRecord(
        amount: 1250.0,
        direction: TransactionDirection.debit,
        channel: TransactionChannel.card,
        accountHint: 'xx5678',
        merchantRaw: 'Swiggy',
        counterpartyVpa: null,
        balanceAfter: null,
        refId: null,
        ts: DateTime.utc(2026, 7, 12, 10, 0),
        parseSource: ParseSource.generic,
        parseConfidence: 0.8,
      );

      final candidate = Transaction(
        id: 'txn_auth_1',
        ts: DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch, // 2 days earlier
        amount: 1250.0,
        direction: 'debit',
        channel: 'card',
        accountHint: 'xx5678',
        merchantRaw: 'Swiggy',
        parseSource: 'generic',
        confidenceJson: '{}',
        status: 'auto',
        isDeleted: false,
        isAnalyticsExcluded: false,
        lifecycleState: 'pending',
        createdAt: DateTime.utc(2026, 7, 10),
        updatedAt: DateTime.utc(2026, 7, 10),
      );

      final result = correlator.correlate(
        record: record,
        candidates: [candidate],
      );

      expect(result, isNotNull);
      expect(result!.matchedTransactionId, 'txn_auth_1');
      expect(result.linkType, TransactionLinkType.settles);
    });
  });
}
