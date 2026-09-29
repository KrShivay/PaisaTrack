import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/constants.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/enrichment/decision_policy.dart';

Future<void> _seedAutoTransactions(
  AppDatabase database, {
  required String category,
  required int count,
  int correctedCount = 0,
  int confirmedCount = 0,
  bool statusOnlyConfirmed = false,
  String parseSource = 'template',
}) async {
  for (var i = 0; i < count; i++) {
    final id = 'txn_${category}_$i';
    final created = DateTime.utc(2026, 7, 1).add(Duration(minutes: i));
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: created.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            categoryId: Value(category),
            parseSource: parseSource,
            confidenceJson: '{"category":{"c":0.8,"src":"seed"}}',
            status: statusOnlyConfirmed ? 'confirmed' : 'auto',
            createdAt: created,
            updatedAt: created,
          ),
        );
    if (i < correctedCount) {
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(id)))
          .write(
        const TransactionsCompanion(
          categoryId: Value('other'),
          status: Value('confirmed'),
        ),
      );
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'fb_${id}_correction',
              txnId: id,
              field: 'category_id',
              oldValue: Value(category),
              newValue: const Value('other'),
              context: 'weekly_review',
              createdAt: created,
            ),
          );
    } else if (i < correctedCount + confirmedCount) {
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(id)))
          .write(const TransactionsCompanion(status: Value('confirmed')));
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'fb_${id}_confirmation',
              txnId: id,
              field: 'status',
              oldValue: const Value('auto'),
              newValue: const Value('confirmed'),
              context: 'sort_confirm',
              createdAt: created,
            ),
          );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const policy = DecisionPolicy();

  DecisionPolicyInput input({
    double merchantConfidence = 0.8,
    double categoryConfidence = 0.8,
    double amount = 499,
    int merchantTxnCount = 0,
    int askBudgetLeft = 2,
    String? counterpartyVpa,
    bool counterpartySeen = true,
  }) {
    return DecisionPolicyInput(
      merchantConfidence: merchantConfidence,
      categoryConfidence: categoryConfidence,
      amount: amount,
      merchantTxnCount: merchantTxnCount,
      askBudgetLeft: askBudgetLeft,
      counterpartyVpa: counterpartyVpa,
      counterpartySeen: counterpartySeen,
    );
  }

  test('table driven status branches', () {
    final cases = [
      (
        name: 'silent high confidence',
        input: input(merchantConfidence: 0.95, categoryConfidence: 0.9),
        status: DecisionStatus.auto,
      ),
      (
        name: 'minimum confidence controls decision',
        input: input(merchantConfidence: 1, categoryConfidence: 0.59),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'medium confidence asks for high amount',
        input: input(amount: 500),
        status: DecisionStatus.asked,
      ),
      (
        name: 'medium confidence asks for familiar merchant',
        input: input(merchantTxnCount: 3),
        status: DecisionStatus.asked,
      ),
      (
        name: 'daily budget exhaustion falls to review',
        input: input(amount: 500, askBudgetLeft: 0),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'medium confidence low amount unfamiliar merchant reviews',
        input: input(amount: 499, merchantTxnCount: 2),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'unseen p2p counterparty asks once',
        input: input(
          merchantConfidence: 0.2,
          categoryConfidence: 0.2,
          counterpartyVpa: 'friend@upi',
          counterpartySeen: false,
        ),
        status: DecisionStatus.asked,
      ),
      (
        name: 'seen p2p counterparty can auto at high confidence',
        input: input(
          merchantConfidence: 1,
          categoryConfidence: 1,
          counterpartyVpa: 'friend@upi',
        ),
        status: DecisionStatus.auto,
      ),
      (
        name: 'seen p2p counterparty still reviews at low confidence',
        input: input(
          merchantConfidence: 0.2,
          categoryConfidence: 0.2,
          counterpartyVpa: 'friend@upi',
        ),
        status: DecisionStatus.needsReview,
      ),
      (
        name: 'unseen p2p respects exhausted ask budget',
        input: input(
          counterpartyVpa: 'friend@upi',
          counterpartySeen: false,
          askBudgetLeft: 0,
        ),
        status: DecisionStatus.needsReview,
      ),
    ];

    for (final c in cases) {
      expect(policy.decide(c.input), c.status, reason: c.name);
    }
  });

  test('wire names match transaction status values', () {
    expect(DecisionStatus.auto.wireName, 'auto');
    expect(DecisionStatus.asked.wireName, 'asked');
    expect(DecisionStatus.needsReview.wireName, 'needs_review');
  });

  group('AdaptiveThresholdPolicy', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await database.seedDefaultCategories();
    });

    tearDown(() async {
      await database.close();
    });

    test('thresholdFor a null category returns the static default', () async {
      final policy = AdaptiveThresholdPolicy(database);
      expect(
        await policy.thresholdFor(null),
        AppConstants.silentConfidenceThreshold,
      );
    });

    test('thresholdFor with no persisted history returns the static default',
        () async {
      final policy = AdaptiveThresholdPolicy(database);
      expect(
        await policy.thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
    });

    test('thresholdFor falls back for a category missing from stored history',
        () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: '{"shopping":0.9}',
            ),
          );
      final policy = AdaptiveThresholdPolicy(database);
      expect(await policy.thresholdFor('shopping'), 0.9);
      expect(
        await policy.thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
    });

    test('thresholdFor returns the default on malformed stored JSON', () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: 'not json',
            ),
          );
      final policy = AdaptiveThresholdPolicy(database);
      expect(
        await policy.thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
    });

    test('recompute skips categories with fewer than 50 explicit outcomes',
        () async {
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 49,
        confirmedCount: 49,
      );
      final result = await AdaptiveThresholdPolicy(database).recompute();
      expect(result, isEmpty);
      expect(await database.select(database.modelMeta).get(), isEmpty);
    });

    test('raises the threshold +0.03 when correction rate exceeds 15%',
        () async {
      // 9/50 = 18% > 15%.
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        correctedCount: 9,
        confirmedCount: 41,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(
        result['food_dining'],
        closeTo(AppConstants.silentConfidenceThreshold + 0.03, 1e-9),
      );
      expect(
        await AdaptiveThresholdPolicy(database).thresholdFor('food_dining'),
        closeTo(AppConstants.silentConfidenceThreshold + 0.03, 1e-9),
      );
    });

    test('lowers the threshold -0.01 on 50 explicit outcomes', () async {
      // 5/50 = 10% <= 15%.
      await _seedAutoTransactions(
        database,
        category: 'shopping',
        count: 50,
        correctedCount: 5,
        confirmedCount: 45,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(
        result['shopping'],
        closeTo(AppConstants.silentConfidenceThreshold - 0.01, 1e-9),
      );
    });

    test('raise is capped at 0.98', () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: '{"groceries":0.97}',
            ),
          );
      await _seedAutoTransactions(
        database,
        category: 'groceries',
        count: 50,
        correctedCount: 9,
        confirmedCount: 41,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(result['groceries'], 0.98);
    });

    test('lower is floored at 0.0', () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: '{"travel":0.0}',
            ),
          );
      await _seedAutoTransactions(
        database,
        category: 'travel',
        count: 50,
        confirmedCount: 50,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(result['travel'], 0.0);
    });

    test('does not reapply the same trailing window twice', () async {
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        confirmedCount: 50,
      );
      final policy = AdaptiveThresholdPolicy(database);

      expect(await policy.recompute(), isNotEmpty);
      expect(await policy.recompute(), isEmpty);
      expect(
        await policy.thresholdFor('food_dining'),
        closeTo(AppConstants.silentConfidenceThreshold - 0.01, 1e-9),
      );
    });

    test('preserves thresholds for categories without a new window', () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: '{"shopping":0.94}',
            ),
          );
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        confirmedCount: 50,
      );

      await AdaptiveThresholdPolicy(database).recompute();

      expect(
        await AdaptiveThresholdPolicy(database).thresholdFor('shopping'),
        0.94,
      );
    });

    test('silent automatic rows and old adaptive v1 state are ignored',
        () async {
      for (final row in [
        ModelMetaCompanion.insert(
          key: 'category_silent_thresholds_v1',
          value: '{"food_dining":0.1}',
        ),
        ModelMetaCompanion.insert(
          key: 'category_threshold_window_counts_v1',
          value: '{"food_dining":50}',
        ),
      ]) {
        await database.into(database.modelMeta).insert(row);
      }
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(result, isEmpty);
      expect(
        await AdaptiveThresholdPolicy(database).thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
      expect(
        (await database.select(database.modelMeta).get())
            .where((row) => row.key == 'category_silent_thresholds_v2'),
        isEmpty,
      );
    });

    test('status-only and manual confirmations are not category evidence',
        () async {
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        statusOnlyConfirmed: true,
      );
      await _seedAutoTransactions(
        database,
        category: 'shopping',
        count: 50,
        confirmedCount: 50,
        parseSource: 'manual',
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(result, isEmpty);
      expect(
        await AdaptiveThresholdPolicy(database).thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
      expect(
        await AdaptiveThresholdPolicy(database).thresholdFor('shopping'),
        AppConstants.silentConfidenceThreshold,
      );
    });
  });
}
