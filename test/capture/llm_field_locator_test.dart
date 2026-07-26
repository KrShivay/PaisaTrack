import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/llm_field_locator.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/intelligence/llm/llm_request.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

void main() {
  final sms = RawSms(
    id: 'unknown-1',
    sender: 'XX-NEWBANK',
    body: 'Rs 1250.00 debited for order at ZOMATO',
    receivedAt: DateTime.utc(2026, 7, 12, 12),
  );

  test('returns a verified record when model returns verbatim quotations', () async {
    final locator = LlmFieldLocator(
      _JsonRuntime({
        'amount_text': '1250.00',
        'direction_text': 'debited',
        'merchant_text': 'ZOMATO',
        'message_kind': 'transactional',
      }),
    );

    final record = await locator.locate(sms);

    expect(record, isNotNull);
    expect(record?.amount, 1250.0);
    expect(record?.direction, TransactionDirection.debit);
    expect(record?.parseSource, ParseSource.localLlm);
    expect(record?.evidence, isNotNull);
    expect(record?.evidence, hasLength(3));
  });

  test('refuses adversarial hallucinated amount not in body text', () async {
    final locator = LlmFieldLocator(
      _JsonRuntime({
        'amount_text': '999.00', // Plausible but absent from body ("Rs 1250.00 debited...")
        'direction_text': 'debited',
        'message_kind': 'transactional',
      }),
    );

    final record = await locator.locate(sms);

    expect(record, isNull);
  });

  test('refuses verbatim formatting mismatch (1,250.00 vs 1250.00) rather than coercing', () async {
    final locator = LlmFieldLocator(
      _JsonRuntime({
        'amount_text': '1,250.00', // Formatting differs from "1250.00" in body
        'direction_text': 'debited',
        'message_kind': 'transactional',
      }),
    );

    final record = await locator.locate(sms);

    expect(record, isNull);
  });

  test('refuses non-transactional messages', () async {
    final locator = LlmFieldLocator(
      _JsonRuntime({
        'amount_text': '1250.00',
        'direction_text': 'debited',
        'message_kind': 'non_transactional',
      }),
    );

    final record = await locator.locate(sms);

    expect(record, isNull);
  });

  test('fails closed when runtime is unavailable', () async {
    expect(
      await const LlmFieldLocator(NoopLlmRuntime()).locate(sms),
      isNull,
    );
  });
}

class _JsonRuntime extends NoopLlmRuntime {
  _JsonRuntime(this.json);

  final Map<String, Object?> json;
  LlmRequest? lastRequest;

  @override
  Future<LlmResult<Map<String, Object?>>> extractJsonRequest(
    LlmRequest request,
    Map<String, Object?> schema,
  ) async {
    lastRequest = request;
    return LlmSuccess(json);
  }
}
