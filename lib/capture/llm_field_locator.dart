import '../core/constants.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import '../intelligence/llm/llm_request.dart';
import '../intelligence/llm/llm_runtime.dart';
import 'span_verifier.dart';
import 'template_engine/field_normalizer.dart';

/// Locates exact verbatim field quotations from SMS text using an on-device model,
/// handing substrings back to [FieldNormalizer] to enforce the numeric trust boundary.
///
/// Model outputs are treated as quotations, not values. A hallucinated or re-formatted
/// amount string is refused.
class LlmFieldLocator {
  const LlmFieldLocator(
    this._runtime, {
    FieldNormalizer fieldNormalizer = const FieldNormalizer(),
    SpanVerifier spanVerifier = const SpanVerifier(),
  })  : _fieldNormalizer = fieldNormalizer,
        _spanVerifier = spanVerifier;

  final LlmRuntime _runtime;
  final FieldNormalizer _fieldNormalizer;
  final SpanVerifier _spanVerifier;

  static const schema = <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': ['amount_text', 'direction_text', 'message_kind'],
    'properties': {
      'amount_text': {'type': 'string'},
      'direction_text': {'type': 'string'},
      'date_text': {'type': 'string'},
      'merchant_text': {'type': 'string'},
      'account_text': {'type': 'string'},
      'message_kind': {
        'type': 'string',
        'enum': ['transactional', 'non_transactional'],
      },
    },
  };

  /// Attempts to locate transaction fields as exact verbatim quotations.
  ///
  /// Returns null when the model output is invalid, non-transactional, or contains
  /// a hallucinated/re-formatted string not present in [sms.body].
  Future<NormalizedTransactionRecord?> locate(RawSms sms) async {
    final result = await _runtime.extractJsonRequest(
      LlmRequest(
        systemInstruction:
            'Locate exact verbatim text snippets from the user-provided SMS for transaction fields. '
            'Return ONLY schema-valid JSON with verbatim quotations from the source message. '
            'Never alter or format quoted text.',
        userMessage: sms.body,
        task: LlmTask.jsonExtraction,
      ),
      schema,
    );
    if (result is! LlmSuccess<Map<String, Object?>>) return null;
    return _validatedRecord(result.value, sms);
  }

  NormalizedTransactionRecord? _validatedRecord(
    Map<String, Object?> json,
    RawSms sms,
  ) {
    if (json['message_kind'] != 'transactional') return null;

    final amountText = _optionalText(json['amount_text']);
    final directionText = _optionalText(json['direction_text']);
    final dateText = _optionalText(json['date_text']);
    final merchantText = _optionalText(json['merchant_text']);
    final accountText = _optionalText(json['account_text']);

    if (amountText == null || directionText == null) return null;

    final body = sms.body;

    // 1. Verbatim assertion for amount: must occur verbatim in source text.
    final amountIndex = body.indexOf(amountText);
    if (amountIndex == -1) return null;

    // 2. Verbatim assertion for direction: must occur verbatim in source text.
    final dirIndex = body.toLowerCase().indexOf(directionText.toLowerCase());
    if (dirIndex == -1) return null;

    final actualDirText = body.substring(dirIndex, dirIndex + directionText.length);

    // Parse values from verbatim substrings through FieldNormalizer
    final double amount;
    try {
      amount = _fieldNormalizer.parseAmount(amountText);
    } catch (_) {
      return null;
    }

    final direction = _parseDirection(directionText);
    if (direction == null) return null;

    final channel = _inferChannel(body);

    // Build verifying evidence list
    final evidence = <FieldEvidence>[
      FieldEvidence(
        field: 'amount',
        start: amountIndex,
        end: amountIndex + amountText.length,
        verbatim: amountText,
        extractor: 'local_llm',
      ),
      FieldEvidence(
        field: 'direction',
        start: dirIndex,
        end: dirIndex + directionText.length,
        verbatim: actualDirText,
        extractor: 'local_llm',
      ),
    ];

    DateTime ts = sms.receivedAt;
    if (dateText != null) {
      final dateIndex = body.indexOf(dateText);
      if (dateIndex != -1) {
        evidence.add(
          FieldEvidence(
            field: 'ts',
            start: dateIndex,
            end: dateIndex + dateText.length,
            verbatim: dateText,
            extractor: 'local_llm',
          ),
        );
      } else {
        evidence.add(
          FieldEvidence(
            field: 'ts',
            start: 0,
            end: body.length,
            verbatim: body,
            extractor: 'local_llm',
          ),
        );
      }
    } else {
      evidence.add(
        FieldEvidence(
          field: 'ts',
          start: 0,
          end: body.length,
          verbatim: body,
          extractor: 'local_llm',
        ),
      );
    }

    final record = NormalizedTransactionRecord(
      amount: amount,
      direction: direction,
      channel: channel,
      merchantRaw: merchantText,
      counterpartyVpa: null,
      accountHint: accountText == null ? null : 'xx$accountText',
      balanceAfter: null,
      refId: null,
      ts: ts,
      parseSource: ParseSource.localLlm,
      parseConfidence: AppConstants.llmParseConfidence,
      evidence: evidence,
    );

    // Verify record evidence with SpanVerifier
    if (!_spanVerifier.verify(body: body, evidence: evidence, record: record)) {
      return null;
    }

    return record;
  }

  TransactionDirection? _parseDirection(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(?:debited|spent|withdrawn|paid|sent|dr)\b').hasMatch(lower)) {
      return TransactionDirection.debit;
    }
    if (RegExp(r'\b(?:credited|received|deposited|refund|reversal|cr)\b').hasMatch(lower)) {
      return TransactionDirection.credit;
    }
    return null;
  }

  TransactionChannel _inferChannel(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('upi')) return TransactionChannel.upi;
    if (lower.contains('card') || lower.contains('pos')) return TransactionChannel.card;
    if (lower.contains('neft') || lower.contains('imps') || lower.contains('rtgs')) {
      return TransactionChannel.netbanking;
    }
    if (lower.contains('atm') || lower.contains('cash')) return TransactionChannel.atm;
    return TransactionChannel.unknown;
  }

  String? _optionalText(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
