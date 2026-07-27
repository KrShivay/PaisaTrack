import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Categorizer categorizer;
  late Map<String, Map<String, int>> memoryStore;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
    memoryStore = {};
    categorizer = Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap.fromJson('{}'),
      merchantMemory: ({merchantRaw, counterpartyVpa}) async {
        final key = merchantRaw ?? counterpartyVpa;
        if (key == null || !memoryStore.containsKey(key)) return null;
        return computeMerchantMemoryHit(confirmedCategoryCounts: memoryStore[key]!);
      },
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('Two consistent confirmations produce a high-confidence memory hit (0.95)', () async {
    memoryStore['Swiggy'] = {'food_dining': 2};

    final record = NormalizedTransactionRecord(
      amount: 450.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'Swiggy',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 7, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );

    final result = await categorizer.categorize(record);
    expect(result.categoryId, 'food_dining');
    expect(result.source, 'merchant_memory');
    expect(result.confidence, closeTo(0.95, 0.01));
  });

  test('Conflicting history lowers confidence rather than picking a winner with false certainty', () async {
    memoryStore['Amazon'] = {'shopping': 2, 'electronics': 1};

    final record = NormalizedTransactionRecord(
      amount: 1500.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.card,
      merchantRaw: 'Amazon',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 7, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );

    // Laplace agreement: (2+1)/(3+2) = 3/5 = 0.60 -> confidence 0.95 * 0.60 = 0.57 (< 0.70 threshold)
    final memoryHit = computeMerchantMemoryHit(confirmedCategoryCounts: memoryStore['Amazon']!);
    expect(memoryHit, isNotNull);
    expect(memoryHit!.confidence, closeTo(0.57, 0.01));

    final result = await categorizer.categorize(record);
    // Since confidence 0.57 < 0.70 threshold, categorizer falls through
    expect(result.source, isNot('merchant_memory'));
  });
}
