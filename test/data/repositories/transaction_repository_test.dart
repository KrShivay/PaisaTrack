import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/category_correction.dart';
import 'package:paisatrack/data/repositories/payee_evidence_repository.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';

Future<void> _seedCategories(AppDatabase database) async {
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'other',
          name: 'Other',
          icon: 'category',
          isSpending: true,
          sortOrder: 1,
          isUserCreated: false,
        ),
      );
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'groceries',
          name: 'Groceries',
          icon: 'shopping_cart',
          isSpending: true,
          sortOrder: 3,
          isUserCreated: false,
        ),
      );
  await database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: 'food_dining',
          name: 'Food & Dining',
          icon: 'restaurant',
          isSpending: true,
          sortOrder: 2,
          isUserCreated: false,
        ),
      );
}

Future<String> _seedMerchant(AppDatabase database, String canonicalName) {
  final id = 'merchant_${canonicalName.toLowerCase()}';
  final now = DateTime.utc(2026, 7, 1);
  return database
      .into(database.merchants)
      .insertOnConflictUpdate(
        MerchantsCompanion.insert(
          id: id,
          canonicalName: canonicalName,
          firstSeen: now,
          lastSeen: now,
        ),
      )
      .then((_) => id);
}

Future<void> _insertTxn(
  AppDatabase database, {
  required String id,
  DateTime? ts,
  String? merchantId,
  String? merchantRaw,
  String? counterpartyVpa,
  String status = 'asked',
  String categoryId = 'other',
  bool isDeleted = false,
  bool isNotTransaction = false,
  String? duplicateOfTxnId,
}) async {
  final now = ts ?? DateTime.utc(2026, 7, 8, 9);
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: now.millisecondsSinceEpoch,
          amount: 250,
          currencyCode: const Value('INR'),
          currencySymbol: const Value('₹'),
          direction: 'debit',
          channel: 'upi',
          merchantId: Value(merchantId),
          merchantRaw: Value(merchantRaw),
          counterpartyVpa: Value(counterpartyVpa),
          categoryId: Value(categoryId),
          isDeleted: Value(isDeleted),
          isNotTransaction: Value(isNotTransaction),
          duplicateOfTxnId: Value(duplicateOfTxnId),
          parseSource: 'template',
          confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
          status: status,
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

Future<void> _insertParseConfirmationCandidate(
  AppDatabase database, {
  required String id,
  String parseSource = 'template',
  String? smsId,
  String? rawSmsBody = 'Paid Rs 250 to Cafe',
  String? evidenceJson =
      '[{"field":"amount","start":9,"end":12,"verbatim":"250","extractor":"regex"}]',
  String confidenceJson =
      '{"parser":{"c":0.74,"src":"template","template_id":"public_v1","provenance":"public"}}',
  bool isDeleted = false,
  bool isNotTransaction = false,
  String? duplicateOfTxnId,
}) async {
  final now = DateTime.utc(2026, 7, 8, 9);
  final candidateSmsId = smsId ?? 'sms_$id';
  if (rawSmsBody != null) {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: candidateSmsId,
            sender: 'XX-BANK',
            body: rawSmsBody,
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
  }
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: now.millisecondsSinceEpoch,
          amount: 250,
          direction: 'debit',
          channel: 'upi',
          categoryId: const Value('other'),
          parseSource: parseSource,
          smsId: Value(rawSmsBody == null ? null : candidateSmsId),
          confidenceJson: confidenceJson,
          status: 'needs_review',
          isDeleted: Value(isDeleted),
          isNotTransaction: Value(isNotTransaction),
          duplicateOfTxnId: Value(duplicateOfTxnId),
          evidenceJson: Value(evidenceJson),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await _seedCategories(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('review queue is bounded while its summary covers every row', () async {
    final merchantId = await _seedMerchant(database, 'Electricity Board');
    for (var index = 0; index < 125; index++) {
      await _insertTxn(
        database,
        id: 'review_$index',
        merchantId: index == 124 ? merchantId : null,
        merchantRaw: index == 124 ? null : 'Payee ${index % 3}',
        status: 'needs_review',
      );
    }
    await _insertTxn(
      database,
      id: 'review_not_transaction',
      status: 'needs_review',
      isNotTransaction: true,
    );
    final repository = TransactionRepository(database);

    final queue = await repository.watchReviewQueue(limit: 100).first;
    final summary = await repository.watchReviewQueueSummary().first;

    expect(queue, hasLength(100));
    expect(summary.count, 125);
    expect(summary.amount, 31250);
    expect(summary.merchantCount, 4);
    expect(summary.highestImpactLabel, isNotEmpty);
  });

  test('status-only Keep and Undo persist and move one row in the review queue',
      () async {
    await _insertTxn(
      database,
      id: 'review_status_only',
      status: 'needs_review',
    );
    final repository = TransactionRepository(database);

    final keepFeedbackCount = await repository.updateWithFeedback(
      txnId: 'review_status_only',
      status: const Value('confirmed'),
      context: 'sort_confirm',
    );

    expect(keepFeedbackCount, 0);
    final keptTransaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('review_status_only')))
        .getSingle();
    expect(keptTransaction.status, 'confirmed');
    expect(await repository.watchReviewQueue().first, isEmpty);
    expect(await database.select(database.feedback).get(), isEmpty);

    final undoFeedbackCount = await repository.updateWithFeedback(
      txnId: 'review_status_only',
      status: const Value('needs_review'),
      context: 'undo_sort',
    );

    expect(undoFeedbackCount, 0);
    final undoneTransaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('review_status_only')))
        .getSingle();
    expect(undoneTransaction.status, 'needs_review');
    final restoredQueue = await repository.watchReviewQueue().first;
    expect(restoredQueue.map((item) => item.id).toList(), [
      'review_status_only',
    ]);
    expect(await database.select(database.feedback).get(), isEmpty);
  });

  test('parse confirmation is explicit, idempotent and reversible', () async {
    await _insertParseConfirmationCandidate(
      database,
      id: 'parse_confirmation',
    );
    await database.into(database.feedback).insert(
          FeedbackCompanion.insert(
            id: 'legacy_parse_confirmation',
            txnId: 'parse_confirmation',
            field: 'parse_verdict',
            newValue: const Value('ok'),
            context: 'parse_confirm',
            createdAt: DateTime.utc(2026, 7, 8),
          ),
        );
    final repository = TransactionRepository(database);
    final beforeConfirmation =
        await repository.watchDetail('parse_confirmation').first;
    expect(beforeConfirmation?.canConfirmParse, isTrue);
    expect(beforeConfirmation?.isParseConfirmed, isFalse);

    expect(
      await repository.confirmParse(
        txnId: 'parse_confirmation',
        clock: () => DateTime.utc(2026, 7, 9),
      ),
      isTrue,
    );
    expect(await repository.confirmParse(txnId: 'parse_confirmation'), isFalse);

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('parse_confirmation')))
        .getSingle();
    expect(transaction.status, 'needs_review');
    expect(transaction.categoryId, 'other');
    final feedback = await database.select(database.feedback).get();
    expect(feedback, hasLength(2));
    final explicit = feedback.singleWhere(
      (row) => row.id == 'fb_parse_confirmation_parse_confirm_v1',
    );
    expect(explicit.field, 'parse_verdict');
    expect(explicit.newValue, 'ok');
    expect(explicit.context, 'parse_confirm');
    expect(explicit.oldValue, 'user_confirmed_v1');
    final afterConfirmation =
        await repository.watchDetail('parse_confirmation').first;
    expect(afterConfirmation?.isParseConfirmed, isTrue);
    expect(
      (await TemplateTrustLedger(database).load())
          .entries['public_v1']
          ?.confirmedParses,
      1,
    );

    expect(
      await repository.undoParseConfirmation(txnId: 'parse_confirmation'),
      isTrue,
    );
    expect(
      await repository.undoParseConfirmation(txnId: 'parse_confirmation'),
      isFalse,
    );
    final remaining = await database.select(database.feedback).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, 'legacy_parse_confirmation');
    final ledger = await TemplateTrustLedger(database).load();
    expect(ledger.entries['public_v1']?.confirmedParses ?? 0, 0);
    final unchanged = await (database.select(database.transactions)
          ..where((row) => row.id.equals('parse_confirmation')))
        .getSingle();
    expect(unchanged.status, 'needs_review');
    expect(unchanged.categoryId, 'other');
  });

  test(
      'parse confirmation rejects manual, imported, unknown and unsupported rows',
      () async {
    await _insertParseConfirmationCandidate(
      database,
      id: 'manual_parse',
      parseSource: 'manual',
    );
    await _insertParseConfirmationCandidate(
      database,
      id: 'imported_parse',
      parseSource: 'unknown',
      rawSmsBody: null,
      confidenceJson: '{"parser":{"c":1,"src":"import"}}',
    );
    await _insertParseConfirmationCandidate(
      database,
      id: 'missing_evidence_parse',
      evidenceJson: null,
    );
    await _insertParseConfirmationCandidate(
      database,
      id: 'purged_sms_parse',
      rawSmsBody: null,
    );
    await _insertParseConfirmationCandidate(
      database,
      id: 'not_transaction_parse',
      isNotTransaction: true,
    );
    await _insertTxn(database, id: 'duplicate_parent');
    await _insertParseConfirmationCandidate(
      database,
      id: 'deleted_parse',
      isDeleted: true,
    );
    await _insertParseConfirmationCandidate(
      database,
      id: 'duplicate_parse',
      duplicateOfTxnId: 'duplicate_parent',
    );
    final repository = TransactionRepository(database);

    for (final id in [
      'manual_parse',
      'imported_parse',
      'missing_evidence_parse',
      'purged_sms_parse',
      'not_transaction_parse',
      'deleted_parse',
      'duplicate_parse',
    ]) {
      expect(await repository.confirmParse(txnId: id), isFalse, reason: id);
      expect(
        (await repository.watchDetail(id).first)?.canConfirmParse,
        isFalse,
        reason: id,
      );
    }
    expect(await database.select(database.feedback).get(), isEmpty);
    expect(
      (await TemplateTrustLedger(database).load()).entries,
      isEmpty,
    );
  });

  test('status and a feedback edit persist together', () async {
    await _insertTxn(
      database,
      id: 'review_status_with_feedback',
      status: 'needs_review',
    );
    final repository = TransactionRepository(database);

    final feedbackCount = await repository.updateWithFeedback(
      txnId: 'review_status_with_feedback',
      categoryId: const Value('food_dining'),
      status: const Value('confirmed'),
      context: 'sort_categorize',
    );

    expect(feedbackCount, 1);
    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('review_status_with_feedback')))
        .getSingle();
    expect(transaction.categoryId, 'food_dining');
    expect(transaction.status, 'confirmed');
    final feedback = await database.select(database.feedback).get();
    expect(feedback, hasLength(1));
    expect(feedback.single.field, 'category_id');
    expect(await repository.watchReviewQueue().first, isEmpty);
  });

  test('Activity page does not report more for exactly 100 visible rows',
      () async {
    for (var index = 0; index < 100; index++) {
      await _insertTxn(database, id: 'activity_$index');
    }

    final page = await TransactionRepository(database)
        .watchTransactionPage(limit: 100)
        .first;

    expect(page.rows, hasLength(100));
    expect(page.hasMore, isFalse);
    expect(page.nextCursor == null, isTrue);
  });

  test('Activity page reports more only when a look-ahead row exists',
      () async {
    for (var index = 0; index < 101; index++) {
      await _insertTxn(database, id: 'activity_$index');
    }

    final page = await TransactionRepository(database)
        .watchTransactionPage(limit: 100)
        .first;

    expect(page.rows, hasLength(100));
    expect(page.hasMore, isTrue);
    expect(page.nextCursor != null, isTrue);
    expect(page.nextCursor?.id, page.rows.last.id);
    expect(page.nextCursor?.ts, page.rows.last.ts.millisecondsSinceEpoch);
  });

  test('evidence id filter returns exactly the requested transaction rows',
      () async {
    for (final id in ['evidence_a', 'unrelated', 'evidence_b']) {
      await _insertTxn(database, id: id);
    }

    final page = await TransactionRepository(database).watchTransactionPage(
      limit: 2,
      transactionIds: {'evidence_a', 'evidence_b'},
    ).first;

    expect(
      page.rows.map((row) => row.id).toSet(),
      {'evidence_a', 'evidence_b'},
    );
    expect(page.hasMore, isFalse);
  });

  test('Activity page excludes deleted and duplicate-suppressed rows',
      () async {
    await _insertTxn(database, id: 'activity_visible');
    await _insertTxn(database, id: 'activity_deleted', isDeleted: true);
    await _insertTxn(
      database,
      id: 'activity_not_transaction',
      isNotTransaction: true,
    );
    await _insertTxn(
      database,
      id: 'activity_suppressed',
      duplicateOfTxnId: 'activity_visible',
    );

    final page = await TransactionRepository(database)
        .watchTransactionPage(limit: 10)
        .first;

    expect(page.rows.map((row) => row.id), ['activity_visible']);
    expect(page.hasMore, isFalse);
  });

  test(
      'Activity keyset pages preserve equal-timestamp order around excluded rows and inserts',
      () async {
    final timestamp = DateTime.utc(2026, 1, 1, 12, 30);
    const visibleCount = 47;
    const pageSize = 7;
    final visibleIds = List.generate(
      visibleCount,
      (index) => 'keyset_${index.toString().padLeft(3, '0')}',
    );
    final expectedIds = [...visibleIds]
      ..sort((left, right) => right.compareTo(left));

    for (final id in visibleIds) {
      await _insertTxn(database, id: id, ts: timestamp);
    }
    for (final id in visibleIds) {
      await _insertTxn(
        database,
        id: '${id}_deleted',
        ts: timestamp,
        isDeleted: true,
      );
      await _insertTxn(
        database,
        id: '${id}_suppressed',
        ts: timestamp,
        duplicateOfTxnId: id,
      );
    }

    final repository = TransactionRepository(database);
    var page = await repository.watchTransactionPage(limit: pageSize).first;
    final actualIds = <String>[];
    var pageIndex = 0;

    while (true) {
      final expectedPage =
          expectedIds.skip(pageIndex * pageSize).take(pageSize);
      final ids = page.rows.map((row) => row.id).toList();
      expect(ids, equals(expectedPage));
      expect(page.rows.every((row) => row.ts == timestamp), isTrue);
      actualIds.addAll(ids);

      final hasExpectedNextPage =
          (pageIndex + 1) * pageSize < expectedIds.length;
      expect(page.hasMore, hasExpectedNextPage);
      if (!hasExpectedNextPage) {
        expect(page.nextCursor == null, isTrue);
        break;
      }

      final lastId = expectedIds[(pageIndex + 1) * pageSize - 1];
      expect(
        page.nextCursor,
        ActivityTransactionCursor(
          ts: timestamp.millisecondsSinceEpoch,
          id: lastId,
        ),
      );

      // This row sorts ahead of the established boundary. Continuing by the
      // last (timestamp, id) pair must not shift or repeat any later page.
      if (pageIndex == 0) {
        await _insertTxn(
          database,
          id: 'keyset_999_inserted_between_pages',
          ts: timestamp,
        );
      }

      page = await repository
          .watchTransactionPage(limit: pageSize, cursor: page.nextCursor)
          .first;
      expect(
        page.rows.map((row) => row.id),
        isNot(contains('keyset_999_inserted_between_pages')),
      );
      pageIndex++;
    }

    expect(actualIds, equals(expectedIds));
    expect(actualIds.toSet(), hasLength(visibleCount));
  });

  group('correctWithRule', () {
    test(
        'writes a learned merchant alias when the transaction is already '
        'resolver-linked', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_1',
        merchantId: merchantId,
        merchantRaw: 'SWIGGY *ORDER 991',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_1',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      final alias = await (database.select(database.merchantAliases)
            ..where((row) => row.alias.equals('SWIGGYORDER991')))
          .getSingle();
      expect(alias.merchantId, merchantId);
      expect(alias.source, 'learned');
      expect(alias.confidence, 1);
    });

    test(
        'does not write an alias when the transaction has no resolved '
        'merchant', () async {
      await _insertTxn(
        database,
        id: 'txn_2',
        merchantId: null,
        merchantRaw: 'SWIGGY *ORDER 991',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_2',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test('does not write an alias when merchantRaw is absent', () async {
      final merchantId = await _seedMerchant(database, 'Friend');
      await _insertTxn(
        database,
        id: 'txn_3',
        merchantId: merchantId,
        merchantRaw: null,
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_3',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      expect(await database.select(database.merchantAliases).get(), isEmpty);
    });

    test(
        'alias write commits atomically with the rule, feedback, and status '
        'update', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_4',
        merchantId: merchantId,
        merchantRaw: 'Swiggy Instamart',
      );

      final feedbackCount =
          await TransactionRepository(database).correctWithRule(
        txnId: 'txn_4',
        categoryId: 'food_dining',
        context: 'weekly_review',
      );

      expect(feedbackCount, greaterThan(0));
      final txn = await (database.select(database.transactions)
            ..where((t) => t.id.equals('txn_4')))
          .getSingle();
      expect(txn.categoryId, 'food_dining');
      expect(txn.status, 'confirmed');
      final rules = await database.select(database.rules).get();
      expect(rules, hasLength(1));
      final alias = await database.select(database.merchantAliases).get();
      expect(alias, hasLength(1));
      expect(alias.single.merchantId, merchantId);
    });

    test(
        'a repeat correction updates the same alias row rather than '
        'duplicating it', () async {
      final merchantId = await _seedMerchant(database, 'Swiggy');
      await _insertTxn(
        database,
        id: 'txn_5',
        merchantId: merchantId,
        merchantRaw: 'Swiggy Instamart',
      );

      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_5',
        categoryId: 'food_dining',
        context: 'ask_now',
      );
      // Second correction on the same normalized alias must upsert, not
      // insert a duplicate primary-key row.
      await _insertTxn(
        database,
        id: 'txn_6',
        merchantId: merchantId,
        merchantRaw: 'swiggy instamart',
        status: 'asked',
      );
      await TransactionRepository(database).correctWithRule(
        txnId: 'txn_6',
        categoryId: 'food_dining',
        context: 'ask_now',
      );

      final aliases = await database.select(database.merchantAliases).get();
      expect(aliases, hasLength(1));
    });
  });

  group('correctCategory scopes', () {
    test('this transaction changes no history and creates no rule', () async {
      await _insertTxn(
        database,
        id: 'current',
        merchantRaw: 'Bookstore',
      );
      await _insertTxn(
        database,
        id: 'history',
        merchantRaw: 'Bookstore',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.thisTransaction,
        context: 'detail_edit',
      );

      expect(result.affectedTransactionCount, 1);
      expect(result.ruleCreated, isFalse);
      final rows = await database.select(database.transactions).get();
      expect(
        rows.singleWhere((row) => row.id == 'current').categoryId,
        'food_dining',
      );
      expect(
        rows.singleWhere((row) => row.id == 'history').categoryId,
        'other',
      );
      expect(await database.select(database.rules).get(), isEmpty);
    });

    test('future scope creates a rule without rewriting history', () async {
      await _insertTxn(
        database,
        id: 'current',
        merchantRaw: 'Bookstore',
      );
      await _insertTxn(
        database,
        id: 'history',
        merchantRaw: 'Bookstore',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.futureMatching,
        context: 'batch_review',
      );

      expect(result.ruleCreated, isTrue);
      expect(result.affectedTransactionCount, 1);
      expect(await database.select(database.rules).get(), hasLength(1));
      final history = await (database.select(database.transactions)
            ..where((row) => row.id.equals('history')))
          .getSingle();
      expect(history.categoryId, 'other');
    });

    test('a second correction replaces the rule for the same payee key',
        () async {
      await _insertTxn(database, id: 'first', merchantRaw: 'Swiggy');
      await _insertTxn(
        database,
        id: 'second',
        merchantRaw: 'SWIGGY!',
        status: 'asked',
      );

      final repository = TransactionRepository(database);
      await repository.correctCategory(
        txnId: 'first',
        categoryId: 'food_dining',
        scope: CorrectionScope.futureMatching,
        context: 'new_merchant',
      );
      final secondCorrection = await repository.correctCategory(
        txnId: 'second',
        categoryId: 'groceries',
        scope: CorrectionScope.futureMatching,
        context: 'new_merchant',
      );

      final rules = await database.select(database.rules).get();
      expect(rules, hasLength(1));
      expect(rules.single.setCategoryId, 'groceries');

      expect(
        await repository.undoRuleMutation(secondCorrection.ruleMutation!),
        isTrue,
      );
      final restored = await database.select(database.rules).get();
      expect(restored, hasLength(1));
      expect(restored.single.setCategoryId, 'food_dining');
    });

    test('existing and future scope updates normalized matching history',
        () async {
      await _insertTxn(
        database,
        id: 'current',
        counterpartyVpa: 'bookstore@ybl',
      );
      await _insertTxn(
        database,
        id: 'matching_history',
        counterpartyVpa: 'BOOKSTORE@YBL',
      );
      await _insertTxn(
        database,
        id: 'other_history',
        counterpartyVpa: 'other@ybl',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'current',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );

      expect(result.affectedTransactionCount, 2);
      expect(result.ruleCreated, isTrue);
      final rows = await database.select(database.transactions).get();
      expect(
        rows
            .where((row) => row.id != 'other_history')
            .every((row) => row.categoryId == 'food_dining'),
        isTrue,
      );
      expect(
        rows.singleWhere((row) => row.id == 'other_history').categoryId,
        'other',
      );
    });

    test('existing and future correction undo restores rows and feedback',
        () async {
      await _insertTxn(
        database,
        id: 'undo_current',
        merchantRaw: 'Bookstore',
        categoryId: 'other',
        status: 'asked',
      );
      await _insertTxn(
        database,
        id: 'undo_history_1',
        merchantRaw: 'BOOKSTORE!',
        categoryId: 'groceries',
        status: 'needs_review',
      );
      await _insertTxn(
        database,
        id: 'undo_history_2',
        merchantRaw: 'Bookstore',
        categoryId: 'food_dining',
        status: 'auto',
      );

      final repository = TransactionRepository(database);
      final result = await repository.correctCategory(
        txnId: 'undo_current',
        categoryId: 'groceries',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
        clock: () => DateTime.utc(2026, 7, 8, 10),
      );
      expect(result.affectedTransactionCount, 3);
      expect(result.ruleMutation!.previousRules, isEmpty);
      expect(
        result.affectedTransactions.map((snapshot) => snapshot.id).toSet(),
        {'undo_current', 'undo_history_1', 'undo_history_2'},
      );
      expect(
        {
          for (final snapshot in result.affectedTransactions)
            snapshot.id: snapshot.feedbackIds.length,
        },
        {
          'undo_current': 2,
          'undo_history_1': 1,
          'undo_history_2': 2,
        },
      );

      expect(await repository.undoCategoryCorrection(result), isTrue);

      final rows = {
        for (final row in await database.select(database.transactions).get())
          row.id: row,
      };
      expect(rows['undo_current']!.categoryId, 'other');
      expect(rows['undo_current']!.status, 'asked');
      expect(rows['undo_history_1']!.categoryId, 'groceries');
      expect(rows['undo_history_1']!.status, 'needs_review');
      expect(rows['undo_history_2']!.categoryId, 'food_dining');
      expect(rows['undo_history_2']!.status, 'auto');
      expect(await database.select(database.rules).get(), isEmpty);
      expect(await database.select(database.feedback).get(), isEmpty);
    });

    test('refused rule restore aborts row and feedback undo atomically',
        () async {
      await _insertTxn(
        database,
        id: 'undo_refused',
        merchantRaw: 'Bookstore',
        categoryId: 'other',
      );
      final repository = TransactionRepository(database);
      final result = await repository.correctCategory(
        txnId: 'undo_refused',
        categoryId: 'groceries',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
        clock: () => DateTime.utc(2026, 7, 8, 10),
      );
      await _insertTxn(database, id: 'another_correction');
      await (database.update(database.rules)
            ..where((row) => row.matchValue.equals('BOOKSTORE')))
          .write(
        const RulesCompanion(
          setCategoryId: Value('food_dining'),
          createdFromTxnId: Value('another_correction'),
        ),
      );

      expect(await repository.undoCategoryCorrection(result), isFalse);

      final row = await (database.select(database.transactions)
            ..where((txn) => txn.id.equals('undo_refused')))
          .getSingle();
      expect(row.categoryId, 'groceries');
      expect(row.status, 'confirmed');
      expect(await database.select(database.feedback).get(), isNotEmpty);
      expect(
        (await database.select(database.rules).get()).single.setCategoryId,
        'food_dining',
      );
    });

    test('matching group updates only explicit ids and creates no rule',
        () async {
      for (final id in ['one', 'two', 'three']) {
        await _insertTxn(database, id: id, merchantRaw: 'Bookstore');
      }

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'one',
        categoryId: 'food_dining',
        scope: CorrectionScope.matchingGroup,
        matchingTxnIds: const {'one', 'two'},
        context: 'batch_review',
      );

      expect(result.affectedTransactionCount, 2);
      expect(result.ruleCreated, isFalse);
      final rows = await database.select(database.transactions).get();
      expect(rows.singleWhere((row) => row.id == 'three').categoryId, 'other');
      expect(await database.select(database.rules).get(), isEmpty);
    });

    test('existing and future scope uses exact normalized merchant identity',
        () async {
      await _insertTxn(
        database,
        id: 'txn_exact',
        merchantRaw: 'Swiggy',
      );
      await _insertTxn(
        database,
        id: 'txn_normalized',
        merchantRaw: 'SWIGGY!',
      );
      await _insertTxn(
        database,
        id: 'txn_instamart',
        merchantRaw: 'Swiggy Instamart',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'txn_exact',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );

      expect(result.affectedTransactionCount, 2);
      final rows = await database.select(database.transactions).get();
      expect(
        rows.singleWhere((row) => row.id == 'txn_exact').categoryId,
        'food_dining',
      );
      expect(
        rows.singleWhere((row) => row.id == 'txn_normalized').categoryId,
        'food_dining',
      );
      expect(
        rows.singleWhere((row) => row.id == 'txn_instamart').categoryId,
        'other',
      );
    });

    test('specific retroactive correction outranks broad legacy rule',
        () async {
      await RuleRepository(database).insert(
        matchType: 'merchant',
        matchValue: 'swiggy',
        setCategoryId: 'food_dining',
        clock: () => DateTime.utc(2026, 7, 7, 10),
      );
      await _insertTxn(
        database,
        id: 'broad_swiggy',
        merchantRaw: 'Swiggy',
      );
      await _insertTxn(
        database,
        id: 'specific_instamart',
        merchantRaw: 'Swiggy Instamart',
      );
      await _insertTxn(
        database,
        id: 'specific_instamart_alt',
        merchantRaw: 'SWIGGY-INSTAMART!',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'specific_instamart',
        categoryId: 'groceries',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );

      expect(result.affectedTransactionCount, 2);
      expect(
        result.affectedTransactions.map((snapshot) => snapshot.id).toSet(),
        {'specific_instamart', 'specific_instamart_alt'},
      );
      final rules = await database.select(database.rules).get();
      expect(rules, hasLength(2));
      final decision = await RuleRepository(database).findMatch(
        merchantRaw: 'Swiggy Instamart',
      );
      expect(decision?.setCategoryId, 'groceries');
      final broad = await (database.select(database.transactions)
            ..where((row) => row.id.equals('broad_swiggy')))
          .getSingle();
      expect(broad.categoryId, 'other');
    });

    test(
        'counterparty matching requires exact VPA and rejects substring over-matches',
        () async {
      await _insertTxn(
        database,
        id: 'txn_exact_vpa',
        counterpartyVpa: 'abc@ybl',
      );
      await _insertTxn(
        database,
        id: 'txn_overmatch_vpa1',
        counterpartyVpa: 'xabc@ybl2',
      );
      await _insertTxn(
        database,
        id: 'txn_overmatch_vpa2',
        counterpartyVpa: 'notabc@ybl',
      );

      final result = await TransactionRepository(database).correctCategory(
        txnId: 'txn_exact_vpa',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );

      expect(result.affectedTransactionCount, 1);
      final rows = await database.select(database.transactions).get();
      expect(
        rows.singleWhere((row) => row.id == 'txn_exact_vpa').categoryId,
        'food_dining',
      );
      expect(
        rows.singleWhere((row) => row.id == 'txn_overmatch_vpa1').categoryId,
        'other',
      );
      expect(
        rows.singleWhere((row) => row.id == 'txn_overmatch_vpa2').categoryId,
        'other',
      );
    });

    test(
        'existing and future scope handles single quotes and prevents SQL injection',
        () async {
      await _insertTxn(
        database,
        id: 't1',
        merchantRaw: "Domino's Pizza",
      );
      await _insertTxn(
        database,
        id: 't2',
        merchantRaw: 'Swiggy',
      );
      await _insertTxn(
        database,
        id: 't3',
        merchantRaw: 'Amazon',
      );

      final result1 = await TransactionRepository(database).correctCategory(
        txnId: 't1',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );
      expect(result1.affectedTransactionCount, 1);

      await _insertTxn(
        database,
        id: 't_inj',
        merchantRaw: "x' OR 1=1 --",
      );

      final result2 = await TransactionRepository(database).correctCategory(
        txnId: 't_inj',
        categoryId: 'food_dining',
        scope: CorrectionScope.existingAndFuture,
        context: 'historical_cleanup',
      );
      expect(result2.affectedTransactionCount, 1);
      final rows = await database.select(database.transactions).get();
      expect(
        rows.singleWhere((row) => row.id == 't_inj').categoryId,
        'food_dining',
      );
      expect(rows.singleWhere((row) => row.id == 't2').categoryId, 'other');
      expect(rows.singleWhere((row) => row.id == 't3').categoryId, 'other');
    });
  });
}
