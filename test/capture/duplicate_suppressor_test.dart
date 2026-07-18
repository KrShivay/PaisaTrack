import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/duplicate_suppressor.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';

class _Case {
  const _Case({
    required this.description,
    required this.candidate,
    required this.existing,
    required this.expectDuplicate,
  });

  final String description;
  final NormalizedTransactionRecord candidate;
  final Transaction existing;
  final bool expectDuplicate;
}

NormalizedTransactionRecord _record({
  double amount = 449,
  TransactionDirection direction = TransactionDirection.debit,
  String? merchantRaw,
  String? counterpartyVpa,
  String? refId,
  required DateTime ts,
}) {
  return NormalizedTransactionRecord(
    amount: amount,
    direction: direction,
    channel: TransactionChannel.upi,
    merchantRaw: merchantRaw,
    counterpartyVpa: counterpartyVpa,
    accountHint: 'xx4521',
    balanceAfter: null,
    refId: refId,
    ts: ts,
    parseSource: ParseSource.template,
    parseConfidence: 0.95,
  );
}

Transaction _existing({
  double amount = 449,
  String direction = 'debit',
  String? merchantRaw,
  String? refId,
  bool isDeleted = false,
  String? duplicateOfTxnId,
  required DateTime ts,
}) {
  return Transaction(
    id: 'txn_existing',
    ts: ts.toUtc().millisecondsSinceEpoch,
    amount: amount,
    direction: direction,
    channel: 'upi',
    accountHint: 'xx4521',
    merchantRaw: merchantRaw,
    merchantId: null,
    categoryId: null,
    description: null,
    balanceAfter: null,
    refId: refId,
    parseSource: 'template',
    smsId: 'sms_existing',
    confidenceJson: '{}',
    status: 'auto',
    isDeleted: isDeleted,
    duplicateOfTxnId: duplicateOfTxnId,
    isAnalyticsExcluded: false,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  final baseTs = DateTime.utc(2026, 7, 5, 10, 30);
  const suppressor = DuplicateSuppressor();

  final cases = <_Case>[
    _Case(
      description:
          'paired-duplicate: bank SMS (vpa) + wallet SMS (merchant), same '
          'amount, 4 minutes apart',
      candidate: _record(
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 4)),
      ),
      // SmsIngestor persists the VPA into merchantRaw when a template has no
      // merchant text (bank UPI-debit alerts), so the stored row looks like
      // this even though the record itself only ever had counterpartyVpa.
      existing: _existing(merchantRaw: 'amazon@ybl', ts: baseTs),
      expectDuplicate: true,
    ),
    _Case(
      description: 'paired-duplicate: matching UPI ref id overrides '
          'mismatched counterparty text',
      candidate: _record(
        merchantRaw: 'Some Other Label',
        refId: 'RRN123456',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(
        merchantRaw: 'Different Label',
        refId: 'RRN123456',
        ts: baseTs,
      ),
      expectDuplicate: true,
    ),
    _Case(
      description: 'near-miss-not-duplicate: same counterparty and amount '
          'but outside the pairing window',
      candidate: _record(
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 45)),
      ),
      existing: _existing(merchantRaw: 'amazon@ybl', ts: baseTs),
      expectDuplicate: false,
    ),
    _Case(
      description: 'near-miss-not-duplicate: same counterparty and time but '
          'amount differs',
      candidate: _record(
        amount: 450,
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(merchantRaw: 'amazon@ybl', ts: baseTs),
      expectDuplicate: false,
    ),
    _Case(
      description: 'unrelated: different direction rules out a refund vs '
          'debit collision',
      candidate: _record(
        direction: TransactionDirection.credit,
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(merchantRaw: 'amazon@ybl', ts: baseTs),
      expectDuplicate: false,
    ),
    _Case(
      description: 'unrelated: same amount/time window but unrelated '
          'counterparties',
      candidate: _record(
        merchantRaw: 'Swiggy',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(merchantRaw: 'Netflix', ts: baseTs),
      expectDuplicate: false,
    ),
    _Case(
      description: 'unrelated: already-suppressed existing row is never a '
          'match target',
      candidate: _record(
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(
        merchantRaw: 'amazon@ybl',
        ts: baseTs,
        isDeleted: true,
      ),
      expectDuplicate: false,
    ),
    _Case(
      description: 'unrelated: an existing row already linked as someone '
          "else's echo (duplicate_of_txn_id set) is never a match target",
      candidate: _record(
        merchantRaw: 'Amazon Pay India',
        ts: baseTs.add(const Duration(minutes: 1)),
      ),
      existing: _existing(
        merchantRaw: 'amazon@ybl',
        ts: baseTs,
        duplicateOfTxnId: 'txn_primary',
      ),
      expectDuplicate: false,
    ),
  ];

  for (final testCase in cases) {
    test(testCase.description, () {
      expect(
        suppressor.isDuplicate(testCase.candidate, testCase.existing),
        testCase.expectDuplicate,
      );
    });
  }
}
