import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _FakeLlmRuntime implements LlmRuntime {
  _FakeLlmRuntime(this.reason);
  final LlmUnavailableReason reason;

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async =>
      LlmUnavailable(reason);

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      LlmUnavailable(reason);

  @override
  Future<bool> isModelAvailable() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<bool> deleteModel() async => true;
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<String> askWith(LlmUnavailableReason reason) => AssistantController(
        runtime: _FakeLlmRuntime(reason),
        database: database,
      ).ask('how much did I spend this month');

  test('modelAbsent tells the user to download the model', () async {
    expect(
      await askWith(LlmUnavailableReason.modelAbsent),
      contains('Download the model in Settings'),
    );
  });

  test('unsupportedDevice names the device, not the missing model', () async {
    final message = await askWith(LlmUnavailableReason.unsupportedDevice);
    expect(message, contains('memory'));
    expect(message, isNot(contains('Download the model')));
  });

  test('failure (e.g. unparsable model output) asks to rephrase, not redownload',
      () async {
    final message = await askWith(LlmUnavailableReason.failure);
    expect(message, contains('rephrasing'));
    expect(message, isNot(contains('Download the model')));
  });

  test('featureDisabled reports the build flag, not the missing model',
      () async {
    final message = await askWith(LlmUnavailableReason.featureDisabled);
    expect(message, contains('turned off'));
    expect(message, isNot(contains('Download the model')));
  });
}
