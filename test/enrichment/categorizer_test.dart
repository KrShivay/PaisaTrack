import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/local_classifier.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';

NormalizedTransactionRecord _record({
  String? merchantRaw,
  String? counterpartyVpa,
}) {
  return NormalizedTransactionRecord(
    amount: 449,
    direction: TransactionDirection.debit,
    channel: TransactionChannel.upi,
    merchantRaw: merchantRaw,
    counterpartyVpa: counterpartyVpa,
    accountHint: null,
    balanceAfter: null,
    refId: null,
    ts: DateTime.utc(2026, 7, 7, 10),
    parseSource: ParseSource.template,
    parseConfidence: 0.97,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late RuleRepository rules;
  late Categorizer categorizer;

  final seedMap = SeedCategoryMap({
    'amzn': 'shopping',
    'swiggy': 'food_dining',
    'zomato': 'food_dining',
    'hdfc': 'fees_charges',
    'hdfc ergo': 'health_insurance',
  });

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    // Rules reference categories via set_category_id and foreign keys are
    // enforced, so the bundled category rows must exist before inserts.
    await database.seedDefaultCategories();
    rules = RuleRepository(database);
    categorizer = Categorizer(rules: rules, seedMap: seedMap);
  });

  tearDown(() async {
    await database.close();
  });

  group('seed map', () {
    test('fromJson parses the bundled format', () {
      final map = SeedCategoryMap.fromJson('{"Uber": "transport"}');
      expect(map.categoryFor('UBER *TRIP HELP.UBER.COM'), 'transport');
    });

    test('prefers the longest matching key', () {
      expect(
        seedMap.categoryFor('HDFC ERGO GENERAL INSURANCE'),
        'health_insurance',
      );
      expect(seedMap.categoryFor('HDFC BANK CHARGES'), 'fees_charges');
    });

    test('returns null for empty or unmatched text', () {
      expect(seedMap.categoryFor(null), isNull);
      expect(seedMap.categoryFor(''), isNull);
      expect(seedMap.categoryFor('Unknown Vendor'), isNull);
    });
  });

  group('ladder (table-driven)', () {
    test('an exact identity rule wins over the seed map', () async {
      // Seed map says food_dining for swiggy; a user rule overrides it.
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'entertainment',
      );

      final result =
          await categorizer.categorize(_record(merchantRaw: 'Swiggy!'));
      expect(result.categoryId, 'entertainment');
      expect(result.confidence, 1.0);
      expect(result.source, 'rule');
      expect(result.ruleId, isNotNull);
    });

    test('counterparty rule matches the exact VPA', () async {
      await rules.insert(
        matchType: 'counterparty',
        matchValue: 'Friend@upi',
        setCategoryId: 'transfers',
      );

      final result =
          await categorizer.categorize(_record(counterpartyVpa: 'friend@upi'));
      expect(result.categoryId, 'transfers');
      expect(result.source, 'rule');
    });

    test('phone-like VPA shape alone stays on the low-confidence fallback',
        () async {
      final result = await categorizer
          .categorize(_record(counterpartyVpa: '9876543210@okaxis'));

      expect(result.categoryId, Categorizer.fallbackCategoryId);
      expect(result.confidence, Categorizer.fallbackConfidence);
      expect(result.source, 'fallback');
    });

    test('an explicit rule can still classify a numeric VPA', () async {
      await rules.insert(
        matchType: 'counterparty',
        matchValue: '9876543210@okaxis',
        setCategoryId: 'transfers',
      );

      final result = await categorizer
          .categorize(_record(counterpartyVpa: '9876543210@okaxis'));

      expect(result.categoryId, 'transfers');
      expect(result.source, 'rule');
    });

    test('counterparty rule (exact identity) beats merchant rule', () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 10),
      );
      await rules.insert(
        matchType: 'counterparty',
        matchValue: 'swiggy@icici',
        setCategoryId: 'subscriptions',
        clock: () => DateTime.utc(2026, 7, 7, 10, 0, 1),
      );

      final result = await categorizer.categorize(
        _record(merchantRaw: 'Swiggy', counterpartyVpa: 'swiggy@icici'),
      );
      expect(result.categoryId, 'subscriptions');
    });

    test('unknown match_type never matches; ladder falls through', () async {
      await rules.insert(
        matchType: 'regex',
        matchValue: 'amzn',
        setCategoryId: 'entertainment',
      );

      final result =
          await categorizer.categorize(_record(merchantRaw: 'AMZN*MKTPLC'));
      expect(result.source, 'seed');
      expect(result.categoryId, 'shopping');
    });

    test('description-only rule applies without changing category confidence',
        () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'AMZN*MKTPLC',
        setDescription: 'Amazon order',
      );

      final result =
          await categorizer.categorize(_record(merchantRaw: 'AMZN*MKTPLC'));
      expect(result.source, 'seed');
      expect(result.categoryId, 'shopping');
      expect(result.confidence, Categorizer.seedConfidence);
      expect(result.ruleId, isNull);
      expect(result.description, 'Amazon order');
    });

    test('memory descriptions do not write without a matched user rule',
        () async {
      final categorizerWithMemory = Categorizer(
        rules: rules,
        seedMap: seedMap,
        merchantMemory: ({merchantRaw, counterpartyVpa}) async =>
            const CategorizationResult(
          categoryId: 'shopping',
          confidence: .99,
          source: 'merchant_memory',
          description: 'Unreviewed memory text',
        ),
      );

      final result = await categorizerWithMemory
          .categorize(_record(merchantRaw: 'Unknown Merchant'));

      expect(result.source, 'merchant_memory');
      expect(result.confidence, .99);
      expect(result.description, isNull);
    });

    test('LLM descriptions do not write without a matched user rule', () async {
      final categorizerWithSuggestion = Categorizer(
        rules: rules,
        seedMap: seedMap,
        llmSuggester: (_) async => const CategorizationResult(
          categoryId: 'shopping',
          confidence: .7,
          source: 'llm_suggestion',
          description: 'Unreviewed model text',
        ),
      );

      final result = await categorizerWithSuggestion
          .categorize(_record(merchantRaw: 'Unknown Merchant'));

      expect(result.source, 'llm_suggestion');
      expect(result.confidence, .7);
      expect(result.description, isNull);
    });

    test('seed map falls back to the VPA when merchant text is absent',
        () async {
      final result = await categorizer
          .categorize(_record(counterpartyVpa: 'zomato@paytm'));
      expect(result.source, 'seed');
      expect(result.categoryId, 'food_dining');
    });

    test('nothing matches -> Other at 0.3, guaranteed review entry', () async {
      final result =
          await categorizer.categorize(_record(merchantRaw: 'Corner Store'));
      expect(result.categoryId, Categorizer.fallbackCategoryId);
      expect(result.confidence, Categorizer.fallbackConfidence);
      expect(result.source, 'fallback');
      expect(result.ruleId, isNull);
    });

    test('classifier uses the winning category adaptive threshold', () async {
      final model = ClassifierModel(
        categories: const ['food_dining', 'shopping'],
        weights: [
          List.filled(LocalClassifier.defaultFeatureCount, 0.0),
          List.filled(LocalClassifier.defaultFeatureCount, 0.0),
        ],
        biases: const [2, 0],
      );
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: classifierModelMetaKey,
              value: model.toJson(),
            ),
          );
      final strict = Categorizer(
        rules: rules,
        seedMap: seedMap,
        classifier: LocalClassifier(database),
        classifierThreshold: (_) async => 0.9,
      );
      final permissive = Categorizer(
        rules: rules,
        seedMap: seedMap,
        classifier: LocalClassifier(database),
        classifierThreshold: (_) async => 0.8,
      );

      expect(
        (await strict.categorize(_record(merchantRaw: 'Swiggy'))).source,
        'seed',
      );
      expect(
        (await permissive.categorize(_record(merchantRaw: 'Swiggy'))).source,
        'classifier',
      );
    });
  });

  group('rule repository', () {
    test('exact VPA rule outranks merchant id and raw merchant rules',
        () async {
      await rules.insert(
        matchType: 'counterparty',
        matchValue: 'swiggy@ybl',
        setCategoryId: 'groceries',
      );
      await rules.insert(
        matchType: 'merchant_id',
        matchValue: 'merchant_swiggy',
        setCategoryId: 'food_dining',
      );

      final result = await categorizer.categorize(
        _record(merchantRaw: 'SWIGGY', counterpartyVpa: 'swiggy@ybl'),
        merchantId: 'merchant_swiggy',
      );

      expect((result.source, result.categoryId), ('rule', 'groceries'));
    });

    test('merchant id rule outranks exact name and legacy fallback', () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'SWIGGY',
        setCategoryId: 'groceries',
      );
      await rules.insert(
        matchType: 'merchant_legacy',
        matchValue: 'swiggy',
        setCategoryId: 'other',
      );
      await rules.insert(
        matchType: 'merchant_id',
        matchValue: 'merchant_swiggy',
        setCategoryId: 'food_dining',
      );

      final result = await rules.findMatch(
        merchantId: 'merchant_swiggy',
        merchantRaw: 'Swiggy',
      );

      expect(result?.setCategoryId, 'food_dining');
    });

    test('legacy merchant rules match on word boundaries after exact tier',
        () async {
      await rules.insert(
        matchType: 'merchant_legacy',
        matchValue: '  SWIGGY ',
        setCategoryId: 'food_dining',
      );

      final match = await rules.findMatch(merchantRaw: 'swiggy!');
      expect(match?.setCategoryId, 'food_dining');

      expect(
        (await rules.findMatch(merchantRaw: 'Swiggy Instamart'))?.setCategoryId,
        'food_dining',
      );
      expect(await rules.findMatch(merchantRaw: 'NotSwiggy'), isNull);
      expect(await rules.findMatch(merchantRaw: 'zomato'), isNull);
    });

    test('new merchant rules are exact and never use legacy fallback',
        () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'SWIGGY',
        setCategoryId: 'food_dining',
      );

      expect(
        (await rules.findMatch(merchantRaw: 'Swiggy Instamart')),
        isNull,
      );
      expect(
        (await categorizer.categorize(
          _record(merchantRaw: 'Swiggy Instamart'),
        ))
            .source,
        'seed',
      );
    });

    test('replacing a legacy merchant rule makes it exact', () async {
      final now = DateTime.utc(2026, 7, 7, 10);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'corrected_txn',
              ts: now.millisecondsSinceEpoch,
              amount: 449,
              direction: 'debit',
              channel: 'upi',
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await rules.insert(
        matchType: 'merchant_legacy',
        matchValue: 'SWIGGY',
        setCategoryId: 'food_dining',
      );

      await rules.replaceForIdentity(
        matchType: 'merchant',
        matchValue: 'SWIGGY',
        setCategoryId: 'groceries',
        createdFromTxnId: 'corrected_txn',
        now: now,
      );

      final stored = await database.select(database.rules).getSingle();
      expect(stored.matchType, 'merchant');
      expect(
        (await rules.findMatch(merchantRaw: 'Swiggy Instamart')),
        isNull,
      );
      expect(
        (await rules.findMatch(merchantRaw: 'Swiggy'))?.setCategoryId,
        'groceries',
      );
    });

    test('exact normalized merchant tier beats a newer broad fallback',
        () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 10),
      );
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy instamart',
        setCategoryId: 'groceries',
        clock: () => DateTime.utc(2026, 7, 7, 9),
      );

      final match = await rules.findMatch(merchantRaw: 'Swiggy Instamart');
      expect(match?.setCategoryId, 'groceries');
    });

    test('newest word-boundary fallback wins within its tier', () async {
      await rules.insert(
        matchType: 'merchant_legacy',
        matchValue: 'swiggy',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 9),
      );
      await rules.insert(
        matchType: 'merchant_legacy',
        matchValue: 'swiggy instamart',
        setCategoryId: 'groceries',
        clock: () => DateTime.utc(2026, 7, 7, 10),
      );

      final match =
          await rules.findMatch(merchantRaw: 'Swiggy Instamart Express');
      expect(match?.setCategoryId, 'groceries');
    });

    test('legacy duplicate identities resolve to the newest rule', () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'SWIGGY',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 10),
      );
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'groceries',
        clock: () => DateTime.utc(2026, 7, 7, 11),
      );

      final match = await rules.findMatch(merchantRaw: 'Swiggy');
      expect(match?.setCategoryId, 'groceries');
    });

    test('incrementHitCount increments only the applied rule', () async {
      final appliedId = await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'food_dining',
      );
      final otherId = await rules.insert(
        matchType: 'merchant',
        matchValue: 'zomato',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 10, 0, 1),
      );

      await rules.incrementHitCount(appliedId);
      await rules.incrementHitCount(appliedId);

      final all = await database.select(database.rules).get();
      final byId = {for (final rule in all) rule.id: rule};
      expect(byId[appliedId]!.hitCount, 2);
      expect(byId[otherId]!.hitCount, 0);
    });
  });
}
