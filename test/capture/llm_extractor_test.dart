import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/llm_extractor.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/intelligence/llm/llm_request.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

void main() {
  final sms = RawSms(
    id: 'unknown-1',
    sender: 'XX-NEWBANK',
    body: 'sanitized unmatched transaction',
    receivedAt: DateTime.utc(2026, 7, 12, 12),
  );

  test('returns a capped local-LLM record for valid model fields', () async {
    final extractor = LlmExtractor(
      _JsonRuntime({
        'amount': 499.0,
        'direction': 'debit',
        'channel': 'upi',
        'merchant_raw': 'Store',
        'ts': DateTime.utc(2026, 7, 12, 11).millisecondsSinceEpoch,
        'parse_confidence': 0.94,
      }),
    );

    final record = await extractor.extract(sms);

    expect(record?.amount, 499);
    expect(record?.parseSource, ParseSource.localLlm);
    expect(record?.parseConfidence, 0.75);
  });

  test('rejects invalid amount and future timestamp', () async {
    for (final json in [
      {
        'amount': 0.0,
        'direction': 'debit',
        'channel': 'upi',
        'ts': DateTime.utc(2026, 7, 12, 11).millisecondsSinceEpoch,
        'parse_confidence': 0.7,
      },
      {
        'amount': 10.0,
        'direction': 'debit',
        'channel': 'upi',
        'ts': DateTime.utc(2026, 7, 14).millisecondsSinceEpoch,
        'parse_confidence': 0.7,
      },
    ]) {
      expect(await LlmExtractor(_JsonRuntime(json)).extract(sms), isNull);
    }
  });

  test('fails closed when runtime is unavailable', () async {
    expect(
      await const LlmExtractor(NoopLlmRuntime()).extract(sms),
      isNull,
    );
  });

  test('keeps SMS data in the user role', () async {
    final runtime = _JsonRuntime({
      'amount': 499.0,
      'direction': 'debit',
      'channel': 'upi',
      'ts': DateTime.utc(2026, 7, 12, 11).millisecondsSinceEpoch,
      'parse_confidence': 0.7,
    });

    await LlmExtractor(runtime).extract(sms);

    expect(runtime.lastRequest?.task, LlmTask.jsonExtraction);
    expect(runtime.lastRequest?.userMessage, sms.body);
    expect(runtime.lastRequest?.systemInstruction, isNot(contains(sms.body)));
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

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async =>
      LlmSuccess(json);
}
