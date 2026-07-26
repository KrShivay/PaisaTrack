import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/llm/llm_request.dart';
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
    expect(calls.single.arguments, {
      'systemInstruction': "Follow the user's instruction.",
      'userMessage': 'private SMS',
      'task': 'narrative',
    });
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

  test('extractJsonRequest puts schema in system instruction', () async {
    String? request;
    Map<Object?, Object?>? arguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments as Map<Object?, Object?>;
      request = arguments!['systemInstruction'] as String;
      return '{"status":"ok"}';
    });

    final result = await runtime.extractJsonRequest(
      const LlmRequest(
        systemInstruction: 'Return status.',
        userMessage: 'Set status to ok.',
        task: LlmTask.jsonExtraction,
      ),
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
    expect(request, contains('"status"'));
    expect(arguments!['userMessage'], 'Set status to ok.');
    expect(arguments!['task'], 'jsonExtraction');
  });

  test('extractJsonRequest rejects non-empty thinking output', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return '<think>private reasoning</think>{"status":"ok"}';
    });

    final result = await runtime.extractJsonRequest(
      const LlmRequest(
        systemInstruction: 'Return status.',
        userMessage: 'Set status to ok.',
        task: LlmTask.jsonExtraction,
      ),
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

    expect(result, isA<LlmUnavailable<Map<String, Object?>>>());
  });

  test('extractJsonRequest permits an empty leading thinking block', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return '<think> </think>\n{"status":"ok"}';
    });

    final result = await runtime.extractJsonRequest(
      const LlmRequest(
        systemInstruction: 'Return status.',
        userMessage: 'Literal /think in user data is not output markup.',
        task: LlmTask.jsonExtraction,
      ),
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
  });

  test('completeRequest rejects blank fields without a platform call',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return 'unused';
    });

    final result = await runtime.completeRequest(
      const LlmRequest(
        systemInstruction: ' ',
        userMessage: 'question',
        task: LlmTask.assistantIntent,
      ),
    );

    expect(result, isA<LlmUnavailable<String>>());
    expect(calls, 0);
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

  test('modelStatus parses native metadata defensively', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {
        'modelId': 'qwen3-0.6b-mixed-int4',
        'displayName': 'Qwen3 0.6B',
        'sizeBytes': 497664000,
        'runtime': 'LiteRT-LM 0.14.0',
        'quantization': 'mixed INT4',
        'contextTokens': 2048,
        'installed': true,
        'supported': true,
        'supportReason': 'supported',
        'backend': 'CPU',
        'downloadState': 'installed',
        'downloadedBytes': 497664000,
      };
    });

    final status = await runtime.modelStatus();

    expect(status.displayName, 'Qwen3 0.6B');
    expect(status.sizeBytes, 497664000);
    expect(status.installed, isTrue);
    expect(status.supported, isTrue);
  });

  test('downloadModelResult preserves typed platform failure code', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'insufficient_storage');
    });

    final result = await runtime.downloadModelResult();

    expect(result.success, isFalse);
    expect(result.code, 'insufficient_storage');
  });
}
