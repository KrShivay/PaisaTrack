import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
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

class _IntentLlmRuntime implements LlmRuntime {
  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async =>
      const LlmSuccess({
        'intent': 'period_total',
        'metric': 'spend',
        'aggregation': 'sum',
        'time_range': {'kind': 'month', 'month': '2026-07'},
      });

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      const LlmSuccess('');

  @override
  Future<bool> isModelAvailable() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> downloadModel() async => true;

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

  test(
      'failure (e.g. unparsable model output) asks to rephrase, not redownload',
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

  test('current-month Ask result includes local July transactions', () async {
    final timestamp = DateTime(2026, 7, 1, 0, 15).toUtc();
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'july_local_txn',
            ts: timestamp.millisecondsSinceEpoch,
            amount: 610.83,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('Zomato'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );

    final answer = await AssistantController(
      runtime: _IntentLlmRuntime(),
      database: database,
      clock: () => DateTime(2026, 7, 1, 0, 30),
    ).ask('How much did I spend this month?');

    expect(answer, contains('₹610.83'));
    expect(answer, contains('2026-07'));
    expect(answer, isNot(contains('No transactions')));
  });
}
