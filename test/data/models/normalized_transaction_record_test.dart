import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';

void main() {
  test('serializes to the frozen normalized transaction contract', () {
    final record = NormalizedTransactionRecord(
      amount: 449,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'AMZN*MKTPLC',
      counterpartyVpa: null,
      accountHint: 'xx4521',
      balanceAfter: 12384.50,
      refId: '615223847712',
      ts: DateTime.fromMillisecondsSinceEpoch(1751702400000, isUtc: true),
      parseSource: ParseSource.localLlm,
      parseConfidence: 0.97,
    );

    expect(record.toJson(), {
      'amount': 449,
      'direction': 'debit',
      'channel': 'upi',
      'merchant_raw': 'AMZN*MKTPLC',
      'counterparty_vpa': null,
      'account_hint': 'xx4521',
      'balance_after': 12384.50,
      'ref_id': '615223847712',
      'ts': 1751702400000,
      'parse_source': 'local_llm',
      'parse_confidence': 0.97,
    });
  });

  test('FieldEvidence serializes and deserializes cleanly', () {
    const evidence = FieldEvidence(
      field: 'amount',
      start: 10,
      end: 15,
      verbatim: '449.00',
      extractor: 'regex_template',
    );

    final json = evidence.toJson();
    expect(json, {
      'field': 'amount',
      'start': 10,
      'end': 15,
      'verbatim': '449.00',
      'extractor': 'regex_template',
    });

    final reconstructed = FieldEvidence.fromJson(json);
    expect(reconstructed, equals(evidence));
  });

  test('NormalizedTransactionRecord includes evidence in toJson when present', () {
    const evidenceList = [
      FieldEvidence(
        field: 'amount',
        start: 5,
        end: 11,
        verbatim: '150.00',
        extractor: 'template',
      ),
    ];
    final record = NormalizedTransactionRecord(
      amount: 150,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'ZOMATO',
      counterpartyVpa: null,
      accountHint: 'xx1234',
      balanceAfter: null,
      refId: null,
      ts: DateTime.fromMillisecondsSinceEpoch(1751702400000, isUtc: true),
      parseSource: ParseSource.template,
      parseConfidence: 1.0,
      evidence: evidenceList,
    );

    final json = record.toJson();
    expect(json['evidence'], [
      {
        'field': 'amount',
        'start': 5,
        'end': 11,
        'verbatim': '150.00',
        'extractor': 'template',
      },
    ]);
  });
}
