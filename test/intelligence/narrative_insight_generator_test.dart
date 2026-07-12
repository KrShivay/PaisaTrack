import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:paisatrack/intelligence/narrative_insight_generator.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('stores a number-free narrative from aggregate payloads', () async {
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'fees_total:2026-07',
            period: '2026-07',
            kind: 'fees_total',
            payloadJson: jsonEncode({'total': 50.0, 'count': 2}),
          ),
        );

    final generated = await NarrativeInsightGenerator(
      database,
      const _TextRuntime('Fees were a notable pattern this month.'),
      enabled: true,
    ).run(today: DateTime.utc(2026, 7, 12));

    expect(generated, isTrue);
    final row = await (database.select(database.insights)
          ..where((entry) => entry.kind.equals('narrative')))
        .getSingle();
    expect(jsonDecode(row.payloadJson)['body'], contains('Fees'));
  });

  test('rejects model-authored numbers', () async {
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'forecast:2026-07',
            period: '2026-07',
            kind: 'forecast',
            payloadJson: '{}',
          ),
        );

    final generated = await NarrativeInsightGenerator(
      database,
      const _TextRuntime('Spending rose by 20 percent.'),
      enabled: true,
    ).run(today: DateTime.utc(2026, 7, 12));

    expect(generated, isFalse);
  });
}

class _TextRuntime extends NoopLlmRuntime {
  const _TextRuntime(this.text);

  final String text;

  @override
  Future<LlmResult<String>> complete(String prompt) async => LlmSuccess(text);
}
