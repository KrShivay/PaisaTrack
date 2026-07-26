import 'dart:math' as math;

import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import '../intelligence/llm/llm_request.dart';
import '../intelligence/llm/llm_runtime.dart';

/// Validates model-proposed fields before producing the frozen parse contract.
class LlmExtractor {
  const LlmExtractor(this._runtime);

  final LlmRuntime _runtime;

  static const schema = <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': ['amount', 'direction', 'channel', 'ts', 'parse_confidence'],
    'properties': {
      'amount': {'type': 'number'},
      'direction': {
        'type': 'string',
        'enum': ['debit', 'credit'],
      },
      'channel': {
        'type': 'string',
        'enum': ['upi', 'card', 'netbanking', 'atm', 'wallet', 'unknown'],
      },
      'merchant_raw': {'type': 'string'},
      'counterparty_vpa': {'type': 'string'},
      'account_hint': {'type': 'string'},
      'balance_after': {'type': 'number'},
      'ref_id': {'type': 'string'},
      'ts': {'type': 'integer'},
      'parse_confidence': {'type': 'number'},
    },
  };

  Future<NormalizedTransactionRecord?> extract(RawSms sms) async {
    final result = await _runtime.extractJsonRequest(
      LlmRequest(
        systemInstruction:
            'Extract exactly one completed financial transaction from the '
            'user-provided SMS. Omit unknown optional fields and never guess. '
            'Return only schema-valid JSON.',
        userMessage: sms.body,
        task: LlmTask.jsonExtraction,
      ),
      schema,
    );
    if (result is! LlmSuccess<Map<String, Object?>>) return null;
    return _validatedRecord(result.value, sms.receivedAt.toUtc());
  }

  NormalizedTransactionRecord? _validatedRecord(
    Map<String, Object?> json,
    DateTime receivedAt,
  ) {
    final amount = (json['amount'] as num?)?.toDouble();
    final confidence = (json['parse_confidence'] as num?)?.toDouble();
    final timestamp = json['ts'] as int?;
    if (amount == null ||
        amount <= 0 ||
        !amount.isFinite ||
        confidence == null ||
        confidence < 0 ||
        confidence > 1 ||
        timestamp == null) {
      return null;
    }
    final ts = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
    if (ts.isBefore(DateTime.utc(2000)) ||
        ts.isAfter(receivedAt.add(const Duration(days: 1)))) {
      return null;
    }
    final direction = switch (json['direction']) {
      'debit' => TransactionDirection.debit,
      'credit' => TransactionDirection.credit,
      _ => null,
    };
    final channel = switch (json['channel']) {
      'upi' => TransactionChannel.upi,
      'card' => TransactionChannel.card,
      'netbanking' => TransactionChannel.netbanking,
      'atm' => TransactionChannel.atm,
      'wallet' => TransactionChannel.wallet,
      'unknown' => TransactionChannel.unknown,
      _ => null,
    };
    if (direction == null || channel == null) return null;

    return NormalizedTransactionRecord(
      amount: amount,
      direction: direction,
      channel: channel,
      merchantRaw: _optionalText(json['merchant_raw']),
      counterpartyVpa: _optionalText(json['counterparty_vpa']),
      accountHint: _optionalText(json['account_hint']),
      balanceAfter: (json['balance_after'] as num?)?.toDouble(),
      refId: _optionalText(json['ref_id']),
      ts: ts,
      parseSource: ParseSource.localLlm,
      // A probabilistic parser must never silently win.
      parseConfidence: math.min(confidence, 0.75),
    );
  }

  String? _optionalText(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
