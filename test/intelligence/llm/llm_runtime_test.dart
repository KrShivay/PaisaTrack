import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/llm');
  const runtime = PlatformLlmRuntime(channel: channel, enabled: true);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('feature-off and absent-model paths return typed no-op results',
      () async {
    const disabled = PlatformLlmRuntime(channel: channel, enabled: false);
    expect(
      await disabled.complete('private SMS'),
      isA<LlmUnavailable<String>>().having(
        (value) => value.reason,
        'reason',
        LlmUnavailableReason.featureDisabled,
      ),
    );

    messenger.setMockMethodCallHandler(channel, (call) {
      throw PlatformException(code: 'model_absent');
    });
    expect(
      await runtime.complete('private SMS'),
      isA<LlmUnavailable<String>>().having(
        (value) => value.reason,
        'reason',
        LlmUnavailableReason.modelAbsent,
      ),
    );
  });

  test('complete uses only the inference platform method', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'local answer';
    });

    final result = await runtime.complete('private SMS');

    expect(result, isA<LlmSuccess<String>>());
    expect(calls.map((call) => call.method), ['complete']);
    expect(calls.single.arguments, {'prompt': 'private SMS'});
  });

  test('extractJson validates strict schema in one attempt', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return '{"amount":42,"kind":"debit"}';
    });
    final result = await runtime.extractJson('extract', {
      'type': 'object',
      'properties': {
        'amount': {'type': 'number'},
        'kind': {'type': 'string'},
      },
      'required': ['amount', 'kind'],
      'additionalProperties': false,
    });

    expect(calls, 1);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value,
      {'amount': 42, 'kind': 'debit'},
    );
  });

  test('extractJson rejects extra fields without retrying', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls++;
        return '{"amount":42,"extra":true}';
      },
    );
    final result = await runtime.extractJson('extract', {
      'type': 'object',
      'properties': {
        'amount': {'type': 'number'},
      },
      'required': ['amount'],
      'additionalProperties': false,
    });
    expect(
      result,
      isA<LlmUnavailable<Map<String, Object?>>>().having(
        (value) => value.reason,
        'reason',
        LlmUnavailableReason.failure,
      ),
    );
    expect(calls, 1);
  });

  test('extractJson rejects enum values without retrying', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return '{"kind":"transfer"}';
    });

    final result = await runtime.extractJson('extract', {
      'type': 'object',
      'properties': {
        'kind': {
          'type': 'string',
          'enum': ['debit', 'credit'],
        },
      },
      'required': ['kind'],
      'additionalProperties': false,
    });

    expect(calls, 1);
    expect(
      result,
      isA<LlmUnavailable<Map<String, Object?>>>().having(
        (value) => value.reason,
        'reason',
        LlmUnavailableReason.failure,
      ),
    );
  });

  test('extractJson pulls the object out of markdown fences and prose',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return 'Sure, here you go:\n```json\n{"amount":42,"kind":"debit"}\n```\nLet me know if you need anything else.';
    });
    final result = await runtime.extractJson('extract', {
      'type': 'object',
      'properties': {
        'amount': {'type': 'number'},
        'kind': {'type': 'string'},
      },
      'required': ['amount', 'kind'],
      'additionalProperties': false,
    });

    expect(calls, 1);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value,
      {'amount': 42, 'kind': 'debit'},
    );
  });

  test('extractJson skips an echoed schema and accepts the later values object',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return '{"type":"object","properties":{"status":{"type":"string"}}}'
          '\n{"status":"ok"}';
    });

    final result = await runtime.extractJson('extract', {
      'type': 'object',
      'properties': {
        'status': {
          'type': 'string',
          'enum': ['ok'],
        },
      },
      'required': ['status'],
      'additionalProperties': false,
    });

    expect(calls, 1);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value,
      {'status': 'ok'},
    );
  });

  test('extractJson accepts an object-typed field left open (no properties)',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return '{"intent":"period_total","time_range":{"kind":"month","month":"2026-07"}}';
    });
    final result = await runtime.extractJson('classify', {
      'type': 'object',
      'required': ['intent'],
      'additionalProperties': false,
      'properties': {
        'intent': {'type': 'string'},
        'time_range': {'type': 'object'},
      },
    });

    expect(calls, 1);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value['time_range'],
      {'kind': 'month', 'month': '2026-07'},
    );
  });

  test('extractJson inserts a schema placeholder inside a chat template',
      () async {
    String? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = (call.arguments as Map<Object?, Object?>)['prompt'] as String;
      return '{"status":"ok"}';
    });

    final result = await runtime.extractJson(
      'system\n$llmJsonSchemaPlaceholder\nassistant',
      {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'enum': ['ok'],
          },
        },
        'required': ['status'],
        'additionalProperties': false,
      },
    );

    expect(result, isA<LlmSuccess<Map<String, Object?>>>());
    expect(request, isNot(contains(llmJsonSchemaPlaceholder)));
    expect(request, contains('"status"'));
    expect(request, endsWith('assistant'));
  });

  test('extractJson can validate strictly without prefilling the schema',
      () async {
    String? request;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = (call.arguments as Map<Object?, Object?>)['prompt'] as String;
      return '{"status":"ok"}';
    });

    final result = await runtime.extractJson(
      'field contract\n$llmJsonValidationOnlyPlaceholder\nassistant',
      {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'enum': ['ok'],
          },
        },
        'required': ['status'],
        'additionalProperties': false,
      },
    );

    expect(result, isA<LlmSuccess<Map<String, Object?>>>());
    expect(request, contains('field contract above'));
    expect(request, isNot(contains('"properties"')));
    expect(request, isNot(contains(llmJsonValidationOnlyPlaceholder)));
  });

  test('fake no-op runtime lets callers degrade without throwing', () async {
    const fake = NoopLlmRuntime();
    expect(await fake.complete('raw SMS'), isA<LlmUnavailable<String>>());
    expect(
      await fake.extractJson('raw SMS', const {}),
      isA<LlmUnavailable<Map<String, Object?>>>(),
    );
  });

  test('downloadModelWithRetry retries on failure up to maxRetries', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'downloadModel') {
        calls++;
        return calls == 3;
      }
      return null;
    });

    final success = await runtime.downloadModelWithRetry(
      maxRetries: 3,
      delay: Duration.zero,
    );

    expect(success, isTrue);
    expect(calls, 3);
  });
}
