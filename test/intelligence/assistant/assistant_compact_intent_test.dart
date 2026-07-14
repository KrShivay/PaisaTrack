import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _CompactIntentRuntime implements LlmRuntime {
  _CompactIntentRuntime(this.intent);

  final Map<String, Object?> intent;
  var extractionCalls = 0;

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async {
    extractionCalls++;
    return LlmSuccess(intent);
  }

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      const LlmSuccess('');

  @override
  Future<bool> deleteModel() async => true;

  @override
  Future<bool> downloadModel() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> isModelAvailable() async => true;
}

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<String> askWith(Map<String, Object?> compact) {
    return AssistantController(
      runtime: _CompactIntentRuntime(compact),
      database: database,
      clock: () => DateTime(2026, 7, 13),
    ).ask('Summarize my financial activity this month');
  }

  test('expands compact merchant filter and all-time range', () async {
    final answer = await askWith({
      'i': 'm',
      'q': 's',
      'g': 's',
      'k': 'a',
      'mer': 'Zomato',
    });

    expect(answer, contains('No matching transactions'));
    expect(answer, contains('Zomato'));
  });

  test('expands compact current and comparison month ranges', () async {
    final answer = await askWith({
      'i': 'c',
      'q': 's',
      'g': 's',
      'k': 'm',
      'mo': '2026-07',
      'ck': 'm',
      'cmo': '2026-06',
    });

    expect(answer, contains('Current:'));
    expect(answer, contains('Previous:'));
  });

  test('expands compact recurring intent and applies default future range',
      () async {
    final answer = await askWith({'i': 'r'});

    expect(answer, 'No recurring payments are due in the next 30 days.');
  });
}
