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
    test('rules always win over the seed map', () async {
      // Seed map says food_dining for swiggy; a user rule overrides it.
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'entertainment',
      );

      final result = await categorizer
          .categorize(_record(merchantRaw: 'Swiggy Instamart'));
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

    test('rule without a category is skipped; seed map applies', () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: 'amzn',
        setDescription: 'Amazon order',
      );

      final result =
          await categorizer.categorize(_record(merchantRaw: 'AMZN*MKTPLC'));
      expect(result.source, 'seed');
      expect(result.categoryId, 'shopping');
      expect(result.confidence, Categorizer.seedConfidence);
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
    test('merchant match is a normalized substring check', () async {
      await rules.insert(
        matchType: 'merchant',
        matchValue: '  SWIGGY ',
        setCategoryId: 'food_dining',
      );

      final match = await rules.findMatch(merchantRaw: 'swiggy instamart');
      expect(match, isNotNull);
      expect(match!.setCategoryId, 'food_dining');

      expect(await rules.findMatch(merchantRaw: 'zomato'), isNull);
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
