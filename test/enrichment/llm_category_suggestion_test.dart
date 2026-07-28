import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/decision_policy.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
  });

  test('A 0.99-confidence model suggestion is capped at 0.70 and cannot auto-apply silently', () async {
    final categorizer = Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap.fromJson('{}'),
      llmSuggester: (record) async => const CategorizationResult(
        categoryId: 'custom_inferred',
        confidence: 0.99,
        source: 'llm_raw',
      ),
    );

    final record = NormalizedTransactionRecord(
      amount: 500.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'Unknown Vendor XYZ',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 7, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );

    final result = await categorizer.categorize(record);

    expect(result.categoryId, 'custom_inferred');
    expect(result.source, 'llm_suggestion');
    // Enforce confidence capping at 0.70
    expect(result.confidence, 0.70);

    // DecisionPolicy check: confidence 0.70 must result in review/ask, NEVER silent auto-apply (DecisionStatus.auto)
    const policy = DecisionPolicy();
    final status = policy.decide(
      const DecisionPolicyInput(
        merchantConfidence: 1.0,
        categoryConfidence: 0.70,
        amount: 500.0,
        merchantTxnCount: 1,
        askBudgetLeft: 0,
      ),
    );
    expect(status, isNot(DecisionStatus.auto));
  });
}
