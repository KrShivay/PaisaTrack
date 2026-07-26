import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent_classifier.dart';
import 'package:paisatrack/intelligence/llm/llm_request.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:path_provider/path_provider.dart';

/// Real-device smoke test for the pinned on-device LLM and engine lifecycle:
///
///   flutter run --debug -d <device> -t integration_test/llm_reliability_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const runtime = PlatformLlmRuntime(enabled: true);
  const schema = <String, Object?>{
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['ok'],
      },
    },
    'required': ['status'],
    'additionalProperties': false,
  };
  const request = LlmRequest(
    systemInstruction: 'Return one JSON object only.',
    userMessage: 'Set status to ok.',
    task: LlmTask.jsonExtraction,
  );

  test(
    'model returns valid JSON twice',
    () async {
      expect(await runtime.isDeviceSupported(), isTrue);
      if (!await runtime.isModelAvailable()) {
        final download = await runtime.downloadModelResult();
        expect(
          download.success,
          isTrue,
          reason: 'Pinned model download failed: ${download.code}',
        );
      }
      expect(
        await runtime.isModelAvailable(),
        isTrue,
        reason: 'Pinned model must be installed after download.',
      );

      final latencies = <Duration>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        final stopwatch = Stopwatch()..start();
        final result = await runtime.extractJsonRequest(request, schema);
        stopwatch.stop();
        latencies.add(stopwatch.elapsed);
        expect(result, isA<LlmSuccess<Map<String, Object?>>>());
        expect(
          (result as LlmSuccess<Map<String, Object?>>).value,
          {'status': 'ok'},
        );
      }

      // ignore: avoid_print
      print('LLM DEVICE LATENCY: first=${latencies[0].inMilliseconds}ms, '
          'second=${latencies[1].inMilliseconds}ms');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'full deterministic assistant route stays grounded on repeat',
    () async {
      final tempDir = await getTemporaryDirectory();
      final dbFile = File('${tempDir.path}/llm_reliability_test.db');
      if (dbFile.existsSync()) dbFile.deleteSync();
      final passphrase = await const AndroidKeystoreDatabasePassphraseProvider()
          .getPassphrase();
      final database = AppDatabase(
        openEncryptedDatabase(file: dbFile, passphrase: passphrase),
      );
      addTearDown(() async {
        await database.close();
        if (dbFile.existsSync()) dbFile.deleteSync();
      });
      final controller = AssistantController(
        runtime: runtime,
        database: database,
        clock: () => DateTime(2026, 7, 13),
      );
      const question = 'What is my total outflow for July 2026?';

      final firstStopwatch = Stopwatch()..start();
      final first = await controller.ask(question);
      firstStopwatch.stop();
      expect(first, contains('No matching transactions'));

      final cachedStopwatch = Stopwatch()..start();
      final cached = await controller.ask(question);
      cachedStopwatch.stop();
      expect(cached, first);

      // ignore: avoid_print
      print(
          'ASK DEVICE LATENCY: first=${firstStopwatch.elapsedMilliseconds}ms, '
          'repeat=${cachedStopwatch.elapsedMilliseconds}ms');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'common natural-language paraphrases use the deterministic fast path',
    () async {
      final tempDir = await getTemporaryDirectory();
      final dbFile = File('${tempDir.path}/llm_accuracy_test.db');
      if (dbFile.existsSync()) dbFile.deleteSync();
      final passphrase = await const AndroidKeystoreDatabasePassphraseProvider()
          .getPassphrase();
      final database = AppDatabase(
        openEncryptedDatabase(file: dbFile, passphrase: passphrase),
      );
      await database.seedDefaultCategories();
      addTearDown(() async {
        await database.close();
        if (dbFile.existsSync()) dbFile.deleteSync();
      });
      final categories = (await database.select(database.categories).get())
          .map((row) => row.name)
          .toList(growable: false);
      final controller = AssistantController(
        runtime: runtime,
        database: database,
        clock: () => DateTime(2026, 7, 13),
      );
      const cases = <(String, List<String>)>[
        (
          'Give me a summary of what came in during July 2026',
          ['Period: 2026-07', 'Filters: Income'],
        ),
        (
          'Put June 2026 next to July 2026 for me',
          ['Current:', 'Previous:', 'Difference:'],
        ),
        (
          'Show Amazon activity',
          ['No matching transactions', 'Amazon'],
        ),
        (
          'What bills are about to hit?',
          ['No recurring payments are due'],
        ),
        (
          'Where has all the cash gone lately?',
          ['No matching transactions', 'Filters: Spending'],
        ),
      ];

      final latencies = <int>[];
      for (final (question, expectedFragments) in cases) {
        expect(
          const AssistantIntentClassifier().classify(
            question,
            today: DateTime(2026, 7, 13),
            categoryNames: categories,
          ),
          isNotNull,
          reason: 'Common query must avoid model inference: $question',
        );
        final stopwatch = Stopwatch()..start();
        final answer = await controller.ask(question);
        stopwatch.stop();
        latencies.add(stopwatch.elapsedMilliseconds);
        for (final fragment in expectedFragments) {
          expect(answer, contains(fragment), reason: question);
        }
      }

      // ignore: avoid_print
      print('ASK FAST-PATH LATENCY: ${latencies.join(',')}ms');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
