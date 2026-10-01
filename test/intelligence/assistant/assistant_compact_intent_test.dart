import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/llm/llm_request.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

import 'category_test_data.dart';

class _CompactIntentRuntime extends NoopLlmRuntime {
  _CompactIntentRuntime(this.intent);

  final Map<String, Object?> intent;
  var extractionCalls = 0;
  Map<String, Object?>? lastSchema;

  @override
  Future<LlmResult<Map<String, Object?>>> extractJsonRequest(
    LlmRequest request,
    Map<String, Object?> schema,
  ) async {
    lastSchema = schema;
    return extractJson(request.userMessage, schema);
  }

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
    final now = DateTime.utc(2026, 7, 1);
    for (final (id, month) in [('current', 7), ('previous', 6)]) {
      final date = DateTime.utc(2026, month, 10);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: 10,
              direction: 'debit',
              channel: 'upi',
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'confirmed',
              currencyCode: const Value('INR'),
              currencySymbol: const Value('₹'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final answer = await askWith({
      'i': 'c',
      'q': 's',
      'g': 's',
      'k': 'm',
      'mo': '2026-07',
      'ck': 'm',
      'cmo': '2026-06',
    });

    expect(answer, contains('Current period (this month to date):'));
    expect(
      answer,
      contains('Previous period (the same elapsed days last month):'),
    );
  });

  test(
    'expands compact recurring intent and applies default future range',
    () async {
      final answer = await askWith({'i': 'r'});

      expect(answer, 'No recurring payments are due in the next 30 days.');
    },
  );

  test(
    'compact schema and LLM intent retain both explicit category scopes',
    () async {
      for (final row in seededCategoryRows().where(
        (row) => const {
          'food_dining',
          'food_delivery',
          'groceries',
          'groceries_quick_commerce',
        }.contains(row['id']),
      )) {
        await database.into(database.categories).insert(
              CategoriesCompanion.insert(
                id: row['id']! as String,
                name: row['name']! as String,
                parentId: Value(row['parent_id'] as String?),
                icon: row['icon']! as String,
                isSpending: row['is_spending']! as bool,
                sortOrder: row['sort_order']! as int,
                isUserCreated: row['is_user_created']! as bool,
              ),
            );
      }
      final runtime = _CompactIntentRuntime({
        'i': 'p',
        'q': 's',
        'g': 's',
        'k': 'm',
        'mo': '2026-07',
        'cats': ['Food Delivery', 'Groceries'],
      });
      final answer = await AssistantController(
        runtime: runtime,
        database: database,
        clock: () => DateTime(2026, 7, 13),
      ).ask('Tell me something useful about my money.');

      final properties = runtime.lastSchema!['properties']! as Map;
      expect((properties['cats'] as Map)['type'], 'array');
      expect(answer, contains('No matching transactions'));
      expect(answer, contains('Food Delivery + Groceries'));
    },
  );

  test('compact intent cannot combine cat and cats encodings', () async {
    final answer = await askWith({
      'i': 'p',
      'q': 's',
      'g': 's',
      'k': 'm',
      'mo': '2026-07',
      'cat': 'Food Delivery',
      'cats': ['Food Delivery', 'Groceries'],
    });

    expect(answer, contains('resolve the requested categories safely'));
    expect(answer, isNot(contains('Food Delivery + Groceries')));
  });
}
