import 'dart:convert';

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
              key: 'category_silent_thresholds_v3',
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
              key: 'category_silent_thresholds_v3',
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
      await _seedAutoTransactions(
        database,
        category: 'groceries',
        count: 400,
        correctedCount: 400,
      );

      final result = await AdaptiveThresholdPolicy(database).recompute();

      expect(result['groceries'], 0.98);
    });

    test('does not reapply an unchanged completed evidence snapshot', () async {
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

    test('revises a processed window when later feedback changes its outcome',
        () async {
      await database.into(database.modelMeta).insert(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v2',
              value: '{"food_dining":0.89}',
            ),
          );
      await database.into(database.modelMeta).insert(
            ModelMetaCompanion.insert(
              key: 'category_threshold_window_counts_v2',
              value: '{"food_dining":50}',
            ),
          );
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        correctedCount: 7,
        confirmedCount: 43,
      );
      final policy = AdaptiveThresholdPolicy(database);

      final first = await policy.recompute();
      expect(
        first['food_dining'],
        closeTo(AppConstants.silentConfidenceThreshold - 0.01, 1e-9),
      );

      const transactionId = 'txn_food_dining_7';
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(transactionId)))
          .write(const TransactionsCompanion(categoryId: Value('other')));
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'fb_${transactionId}_later_correction',
              txnId: transactionId,
              field: 'category_id',
              oldValue: const Value('food_dining'),
              newValue: const Value('other'),
              context: 'weekly_review',
              createdAt: DateTime.utc(2026, 7, 10),
            ),
          );

      final revised = await policy.recompute();

      expect(revised.keys, unorderedEquals(['food_dining']));
      expect(
        revised['food_dining'],
        closeTo(AppConstants.silentConfidenceThreshold + 0.03, 1e-9),
      );
      expect(
        await policy.thresholdFor('food_dining'),
        closeTo(AppConstants.silentConfidenceThreshold + 0.03, 1e-9),
      );
    });

    test('replays multiple completed 50-outcome cohorts deterministically',
        () async {
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 100,
        correctedCount: 7,
        confirmedCount: 93,
      );
      final policy = AdaptiveThresholdPolicy(database);

      final result = await policy.recompute();

      expect(
        result['food_dining'],
        closeTo(AppConstants.silentConfidenceThreshold - 0.02, 1e-9),
      );
      expect(await policy.recompute(), isEmpty);
    });

    test('clears learned state after undo or category disappearance', () async {
      await _seedAutoTransactions(
        database,
        category: 'food_dining',
        count: 50,
        confirmedCount: 50,
      );
      await _seedAutoTransactions(
        database,
        category: 'shopping',
        count: 50,
        confirmedCount: 50,
      );
      final policy = AdaptiveThresholdPolicy(database);
      await policy.recompute();

      const undoneTxnId = 'txn_food_dining_49';
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(undoneTxnId)))
          .write(const TransactionsCompanion(status: Value('auto')));
      await (database.update(database.feedback)
            ..where((row) => row.id.equals('fb_${undoneTxnId}_confirmation')))
          .write(
        const FeedbackCompanion(
          newValue: Value('auto'),
          context: Value('undo_sort'),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await (database.update(database.transactions)
              ..where((row) => row.id.equals('txn_shopping_$i')))
            .write(const TransactionsCompanion(isNotTransaction: Value(true)));
      }

      final revised = await policy.recompute();

      expect(revised.keys, unorderedEquals(['food_dining', 'shopping']));
      expect(
        revised['food_dining'],
        AppConstants.silentConfidenceThreshold,
      );
      expect(revised['shopping'], AppConstants.silentConfidenceThreshold);
      expect(
        await policy.thresholdFor('food_dining'),
        AppConstants.silentConfidenceThreshold,
      );
      expect(
        await policy.thresholdFor('shopping'),
        AppConstants.silentConfidenceThreshold,
      );

      for (final key in [
        'category_silent_thresholds_v3',
        'category_threshold_window_counts_v3',
        'category_threshold_evidence_fingerprints_v3',
      ]) {
        final row = await (database.select(database.modelMeta)
              ..where((meta) => meta.key.equals(key)))
            .getSingle();
        expect(jsonDecode(row.value), isEmpty, reason: key);
      }
    });

    test('resets stale threshold for category without an eligible window',
        () async {
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: 'category_silent_thresholds_v3',
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
        AppConstants.silentConfidenceThreshold,
      );
    });

    test('silent rows and v1/v2 adaptive state are ignored', () async {
      for (final row in [
        ModelMetaCompanion.insert(
          key: 'category_silent_thresholds_v1',
          value: '{"food_dining":0.1}',
        ),
        ModelMetaCompanion.insert(
          key: 'category_threshold_window_counts_v1',
          value: '{"food_dining":50}',
        ),
        ModelMetaCompanion.insert(
          key: 'category_silent_thresholds_v2',
          value: '{"food_dining":0.2}',
        ),
        ModelMetaCompanion.insert(
          key: 'category_threshold_window_counts_v2',
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
            .where((row) => row.key == 'category_silent_thresholds_v3'),
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
