import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/merchant_category_suggestion_repository.dart';
import 'package:paisatrack/data/repositories/payee_evidence_repository.dart';

void main() {
  late AppDatabase database;
  late MerchantCategorySuggestionRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = MerchantCategorySuggestionRepository(database);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food',
            name: 'Food',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'travel',
            name: 'Travel',
            icon: 'train',
            isSpending: true,
            sortOrder: 2,
            isUserCreated: false,
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> addTransaction({
    required String id,
    required String? categoryId,
    String merchantRaw = 'Cafe Blue',
    String? counterpartyVpa = 'cafeblue@upi',
    String parseSource = 'template',
    String status = 'confirmed',
    String confidenceJson = '{"category":{"c":0.8,"src":"seed"}}',
    bool isDeleted = false,
    bool isNotTransaction = false,
    bool isAnalyticsExcluded = false,
    String? duplicateOfTxnId,
    String lifecycleState = 'settled',
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: 250,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: Value(merchantRaw),
            counterpartyVpa: Value(counterpartyVpa),
            categoryId: Value(categoryId),
            parseSource: parseSource,
            confidenceJson: confidenceJson,
            status: status,
            isDeleted: Value(isDeleted),
            isNotTransaction: Value(isNotTransaction),
            isAnalyticsExcluded: Value(isAnalyticsExcluded),
            duplicateOfTxnId: Value(duplicateOfTxnId),
            lifecycleState: Value(lifecycleState),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await PayeeEvidenceRepository(database).replaceForTransaction(
      transactionId: id,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
    );
  }

  Future<void> confirm(String id, String context) async {
    await database.into(database.feedback).insert(
          FeedbackCompanion.insert(
            id: 'status_$id',
            txnId: id,
            field: 'status',
            oldValue: const Value('pending'),
            newValue: const Value('confirmed'),
            context: context,
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        );
  }

  Future<Transaction> transactionById(String id) =>
      (database.select(database.transactions)
            ..where((row) => row.id.equals(id)))
          .getSingle();

  test('suggests only a unanimous explicit category from distinct history',
      () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'sort_confirm');
    await addTransaction(id: 'current', categoryId: 'travel');

    final suggestion = await repository.suggestionFor('current');

    expect(suggestion?.categoryId, 'food');
    expect(suggestion?.supportingTransactionCount, 2);
  });

  test('can suggest for a transaction that has no current category', () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'activity_confirm');
    await addTransaction(id: 'current', categoryId: null);

    final suggestion = await repository.suggestionFor('current');

    expect(suggestion?.categoryId, 'food');
  });

  test(
      'abstains on mixed categories, untrusted status, and same-name other VPA',
      () async {
    await addTransaction(id: 'food_1', categoryId: 'food');
    await addTransaction(id: 'travel_1', categoryId: 'travel');
    await confirm('food_1', 'activity_confirm');
    await confirm('travel_1', 'activity_confirm');
    await addTransaction(
      id: 'same-name-other-vpa',
      categoryId: 'food',
      counterpartyVpa: 'different@upi',
    );
    await confirm('same-name-other-vpa', 'activity_confirm');
    await addTransaction(
      id: 'status-only-parse-confirm',
      categoryId: 'food',
      confidenceJson: '{"category":{"c":0.8,"src":"seed"}}',
    );
    await confirm('status-only-parse-confirm', 'parse_confirm');
    await addTransaction(id: 'current', categoryId: 'travel');

    final suggestion = await repository.suggestionFor('current');

    expect(suggestion, isNull);
  });

  test('revalidates at accept and receipt Undo restores category only',
      () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'sort_confirm');
    await addTransaction(
      id: 'current',
      categoryId: 'travel',
      status: 'needs_review',
    );

    final receipt = await repository.acceptSuggestion(
      transactionId: 'current',
      categoryId: 'food',
      expectedTransaction: await transactionById('current'),
      clock: () => DateTime.utc(2026, 1, 3),
      feedbackIdFactory: (id, _) => 'accepted_$id',
    );

    expect(receipt, isNotNull);
    final afterAccept = await (database.select(database.transactions)
          ..where((row) => row.id.equals('current')))
        .getSingle();
    expect(afterAccept.categoryId, 'food');
    expect(afterAccept.status, 'needs_review');
    expect(afterAccept.amount, 250);
    expect(afterAccept.parseSource, 'template');
    final feedback = await (database.select(database.feedback)
          ..where((row) => row.id.equals('accepted_current')))
        .getSingle();
    expect(feedback.context, 'merchant_suggestion_accept');
    expect(feedback.oldValue, 'travel');
    expect(feedback.newValue, 'food');

    expect(await repository.undoSuggestion(receipt!), isTrue);
    final afterUndo = await (database.select(database.transactions)
          ..where((row) => row.id.equals('current')))
        .getSingle();
    expect(afterUndo.categoryId, 'travel');
    expect(afterUndo.status, 'needs_review');
    expect(
      await (database.select(database.feedback)
            ..where((row) => row.id.equals('accepted_current')))
          .get(),
      isEmpty,
    );
  });

  test('stale receipt Undo cannot overwrite a newer category edit', () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'sort_confirm');
    await addTransaction(id: 'current', categoryId: 'travel');
    final receipt = await repository.acceptSuggestion(
      transactionId: 'current',
      categoryId: 'food',
      expectedTransaction: await transactionById('current'),
      clock: () => DateTime.utc(2026, 1, 3),
      feedbackIdFactory: (id, _) => 'accepted_$id',
    );
    expect(receipt, isNotNull);

    await database.into(database.feedback).insert(
          FeedbackCompanion.insert(
            id: 'later-edit',
            txnId: 'current',
            field: 'category_id',
            oldValue: const Value('food'),
            newValue: const Value('travel'),
            context: 'detail_chip_edit',
            createdAt: DateTime.utc(2026, 1, 4),
          ),
        );
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('current')))
        .write(
      TransactionsCompanion(
        categoryId: const Value('travel'),
        updatedAt: Value(DateTime.utc(2026, 1, 4)),
      ),
    );

    expect(await repository.undoSuggestion(receipt!), isFalse);
    final row = await (database.select(database.transactions)
          ..where((transaction) => transaction.id.equals('current')))
        .getSingle();
    expect(row.categoryId, 'travel');
  });

  test('revalidates before accepting a stale or no-op suggestion', () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'activity_confirm');
    await addTransaction(id: 'current', categoryId: 'travel');

    expect(
      await repository.acceptSuggestion(
        transactionId: 'current',
        categoryId: 'travel',
        expectedTransaction: await transactionById('current'),
      ),
      isNull,
    );
    await database.into(database.feedback).insert(
          FeedbackCompanion.insert(
            id: 'current-choice',
            txnId: 'current',
            field: 'category_id',
            oldValue: const Value('travel'),
            newValue: const Value('travel'),
            context: 'detail_chip_edit',
            createdAt: DateTime.utc(2026, 1, 4),
          ),
        );
    expect(
      await repository.acceptSuggestion(
        transactionId: 'current',
        categoryId: 'food',
        expectedTransaction: await transactionById('current'),
      ),
      isNull,
    );
  });

  test('rejects acceptance when displayed transaction snapshot is stale',
      () async {
    await addTransaction(id: 'old_1', categoryId: 'food');
    await addTransaction(id: 'old_2', categoryId: 'food');
    await confirm('old_1', 'activity_confirm');
    await confirm('old_2', 'activity_confirm');
    await addTransaction(id: 'current', categoryId: 'travel');
    final displayedSnapshot = await transactionById('current');
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('current')))
        .write(
      TransactionsCompanion(
        amount: const Value(500),
        updatedAt: Value(DateTime.utc(2026, 1, 5)),
      ),
    );

    expect(
      await repository.acceptSuggestion(
        transactionId: 'current',
        categoryId: 'food',
        expectedTransaction: displayedSnapshot,
      ),
      isNull,
    );
    final current = await transactionById('current');
    expect(current.amount, 500);
    expect(current.categoryId, 'travel');
  });

  test('normalized VPA collisions do not merge exact payees', () async {
    await addTransaction(
      id: 'exact_1',
      categoryId: 'food',
      counterpartyVpa: 'a.b@ybl',
    );
    await addTransaction(
      id: 'exact_2',
      categoryId: 'food',
      counterpartyVpa: 'a.b@ybl',
    );
    await confirm('exact_1', 'activity_confirm');
    await confirm('exact_2', 'activity_confirm');
    await addTransaction(
      id: 'collision_1',
      categoryId: 'travel',
      counterpartyVpa: 'ab@ybl',
    );
    await addTransaction(
      id: 'collision_2',
      categoryId: 'travel',
      counterpartyVpa: 'ab@ybl',
    );
    await confirm('collision_1', 'activity_confirm');
    await confirm('collision_2', 'activity_confirm');
    await addTransaction(
      id: 'current',
      categoryId: 'travel',
      counterpartyVpa: 'a.b@ybl',
    );

    final suggestion = await repository.suggestionFor('current');

    expect(suggestion?.categoryId, 'food');
  });

  test('later untrusted category edit invalidates an older confirmation',
      () async {
    for (final id in ['stale_1', 'stale_2']) {
      await addTransaction(id: id, categoryId: 'food');
      await confirm(id, 'activity_confirm');
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'untrusted_$id',
              txnId: id,
              field: 'category_id',
              oldValue: const Value('food'),
              newValue: const Value('travel'),
              context: 'parse_confirm',
              createdAt: DateTime.utc(2026, 1, 3),
            ),
          );
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(id)))
          .write(
        TransactionsCompanion(
          categoryId: const Value('travel'),
          updatedAt: Value(DateTime.utc(2026, 1, 3)),
        ),
      );
    }
    await addTransaction(id: 'current', categoryId: 'food');

    expect(await repository.suggestionFor('current'), isNull);
  });

  test('stale persisted name evidence cannot teach the previous merchant name',
      () async {
    await addTransaction(
      id: 'eligible',
      categoryId: 'food',
      counterpartyVpa: null,
    );
    await confirm('eligible', 'activity_confirm');
    await addTransaction(
      id: 'stale-index',
      categoryId: 'food',
      counterpartyVpa: null,
    );
    await confirm('stale-index', 'activity_confirm');
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('stale-index')))
        .write(
      TransactionsCompanion(
        merchantRaw: const Value('Different Cafe'),
        updatedAt: Value(DateTime.utc(2026, 1, 4)),
      ),
    );
    await addTransaction(
      id: 'current',
      categoryId: 'travel',
      counterpartyVpa: null,
    );

    expect(await repository.suggestionFor('current'), isNull);
  });

  test('manual, deleted, duplicate, excluded, and unsettled rows do not count',
      () async {
    await addTransaction(id: 'valid', categoryId: 'food');
    await confirm('valid', 'activity_confirm');
    await addTransaction(id: 'duplicate-parent', categoryId: 'food');
    final excluded = <({String id, Map<String, Object?> fields})>[
      (id: 'manual', fields: {'parseSource': 'manual'}),
      (id: 'deleted', fields: {'isDeleted': true}),
      (id: 'not-transaction', fields: {'isNotTransaction': true}),
      (id: 'analytics-excluded', fields: {'isAnalyticsExcluded': true}),
      (id: 'unsettled', fields: {'lifecycleState': 'pending'}),
      (id: 'duplicate', fields: {'duplicateOfTxnId': 'duplicate-parent'}),
    ];
    for (final item in excluded) {
      final values = item.fields;
      await addTransaction(
        id: item.id,
        categoryId: 'food',
        parseSource: values['parseSource'] as String? ?? 'template',
        isDeleted: values['isDeleted'] as bool? ?? false,
        isNotTransaction: values['isNotTransaction'] as bool? ?? false,
        isAnalyticsExcluded: values['isAnalyticsExcluded'] as bool? ?? false,
        lifecycleState: values['lifecycleState'] as String? ?? 'settled',
        duplicateOfTxnId: values['duplicateOfTxnId'] as String?,
      );
      await confirm(item.id, 'activity_confirm');
    }
    await addTransaction(id: 'current', categoryId: 'travel');

    expect(await repository.suggestionFor('current'), isNull);
  });

  test('name-only history with multiple exact VPAs is ambiguous', () async {
    await addTransaction(id: 'vpa_1', categoryId: 'food');
    await addTransaction(
      id: 'vpa_2',
      categoryId: 'food',
      counterpartyVpa: 'another@upi',
    );
    await confirm('vpa_1', 'activity_confirm');
    await confirm('vpa_2', 'activity_confirm');
    await addTransaction(
      id: 'current',
      categoryId: 'travel',
      counterpartyVpa: null,
    );

    expect(await repository.suggestionFor('current'), isNull);
  });
}
