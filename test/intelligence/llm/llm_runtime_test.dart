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

  test('extractJson validates strict schema and retries once', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return calls == 1 ? 'not json' : '{"amount":42,"kind":"debit"}';
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

    expect(calls, 2);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value,
      {'amount': 42, 'kind': 'debit'},
    );
  });

  test('extractJson rejects extra fields after its single retry', () async {
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
    expect(calls, 2);
  });

  test('extractJson retries enum values outside the closed whitelist',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return calls == 1 ? '{"kind":"transfer"}' : '{"kind":"debit"}';
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

    expect(calls, 2);
    expect(
      (result as LlmSuccess<Map<String, Object?>>).value,
      {'kind': 'debit'},
    );
  });

  test('extractJson rejects enum values after its single retry', () async {
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

    expect(calls, 2);
    expect(
      result,
      isA<LlmUnavailable<Map<String, Object?>>>().having(
        (value) => value.reason,
        'reason',
        LlmUnavailableReason.failure,
      ),
    );
  });

  test('fake no-op runtime lets callers degrade without throwing', () async {
    const fake = NoopLlmRuntime();
    expect(await fake.complete('raw SMS'), isA<LlmUnavailable<String>>());
    expect(
      await fake.extractJson('raw SMS', const {}),
      isA<LlmUnavailable<Map<String, Object?>>>(),
    );
  });
}
