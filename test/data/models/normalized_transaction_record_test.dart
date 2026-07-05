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
}
