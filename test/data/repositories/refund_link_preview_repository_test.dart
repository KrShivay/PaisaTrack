import 'dart:io';

import 'package:paisatrack/data/analytics/financial_eligibility.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/refund_link_preview.dart';
import 'package:paisatrack/data/repositories/refund_link_preview_repository.dart';

void main() {
  late AppDatabase database;
  late RefundLinkPreviewRepository repository;
  Directory? persistentTestDirectory;

  final purchaseDate = DateTime.utc(2026, 1, 10, 10);
  final refundDate = DateTime.utc(2026, 3, 12, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = RefundLinkPreviewRepository(database);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'spend',
            name: 'Spend',
            icon: 'basket',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'income',
            name: 'Income',
            icon: 'wallet',
            isSpending: false,
            sortOrder: 2,
            isUserCreated: false,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    final directory = persistentTestDirectory;
    if (directory != null) await directory.delete(recursive: true);
  });

  Future<Transaction> addTransaction({
    required String id,
    required double amount,
    required String direction,
    DateTime? date,
    String? refId = 'ORDER-AB12345',
    String? currencyCode = 'INR',
    String? currencySymbol = '₹',
    String? categoryId = 'spend',
    String lifecycleState = 'settled',
    bool isDeleted = false,
    bool isNotTransaction = false,
    bool isAnalyticsExcluded = false,
    String? duplicateOfTxnId,
    String? ownedTransferId,
  }) async {
    final ts = (date ?? purchaseDate).millisecondsSinceEpoch;
    final now = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: ts,
            amount: amount,
            direction: direction,
            channel: 'upi',
            currencyCode: Value(currencyCode),
            currencySymbol: Value(currencySymbol),
            refId: Value(refId),
            categoryId: Value(categoryId),
            lifecycleState: Value(lifecycleState),
            isDeleted: Value(isDeleted),
            isNotTransaction: Value(isNotTransaction),
            isAnalyticsExcluded: Value(isAnalyticsExcluded),
            duplicateOfTxnId: Value(duplicateOfTxnId),
            ownedTransferId: Value(ownedTransferId),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (database.select(database.transactions)
          ..where((row) => row.id.equals(id)))
        .getSingle();
  }

  Future<void> addLink({
    required String id,
    required String from,
    required String to,
    String type = 'refunds',
  }) async {
    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: id,
            fromTxnId: from,
            toTxnId: to,
            linkType: type,
            basis: 'synthetic_test',
            createdAt: DateTime.utc(2026, 3, 13).millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<Transaction>> allTransactions() =>
      database.select(database.transactions).get();

  Future<List<TransactionLink>> allLinks() =>
      database.select(database.transactionLinks).get();

  test('previews pair dates and partial refund arithmetic without writes',
      () async {
    await addTransaction(
      id: 'purchase',
      amount: 1200,
      direction: 'debit',
      date: purchaseDate,
    );
    await addTransaction(
      id: 'prior-refund',
      amount: 300,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 1)),
    );
    await addLink(id: 'prior-link', from: 'prior-refund', to: 'purchase');
    await addTransaction(
      id: 'new-refund',
      amount: 400,
      direction: 'credit',
      date: refundDate,
    );
    await database.into(database.feedback).insert(
          FeedbackCompanion.insert(
            id: 'existing-feedback',
            txnId: 'new-refund',
            field: 'status',
            oldValue: const Value('auto'),
            newValue: const Value('confirmed'),
            context: 'synthetic-preview-test',
            createdAt: refundDate,
          ),
        );
    final beforeTransactions = await allTransactions();
    final beforeLinks = await allLinks();
    final beforeFeedback = await database.select(database.feedback).get();
    final beforeEligibleDebitTotal = beforeTransactions
        .where(
          (row) => FinancialEligibility.includesSpendingDebit(
            row,
            categoryIsSpending: row.categoryId != 'income',
          ),
        )
        .fold<double>(0, (sum, row) => sum + row.amount);

    final preview = await repository.previewForRefund('new-refund');

    expect(preview.status, RefundLinkPreviewStatus.ready);
    expect(preview.blockReason, isNull);
    expect(preview.refundDate, refundDate);
    expect(preview.refundAmount, 400);
    expect(preview.candidates, hasLength(1));
    final pair = preview.candidates.single;
    expect(pair.originalTransactionId, 'purchase');
    expect(pair.originalDate, purchaseDate);
    expect(pair.originalGrossAmount, 1200);
    expect(pair.existingAdjustmentAmount, 300);
    expect(pair.proposedRefundAmount, 400);
    expect(pair.remainingRefundableAmount, 900);
    expect(await allTransactions(), beforeTransactions);
    expect(await allLinks(), beforeLinks);
    expect(await database.select(database.feedback).get(), beforeFeedback);
    final afterEligibleDebitTotal = (await allTransactions())
        .where(
          (row) => FinancialEligibility.includesSpendingDebit(
            row,
            categoryIsSpending: row.categoryId != 'income',
          ),
        )
        .fold<double>(0, (sum, row) => sum + row.amount);
    expect(afterEligibleDebitTotal, beforeEligibleDebitTotal);
  });

  test('allows the remaining amount exactly and blocks an over-cap refund',
      () async {
    await addTransaction(id: 'purchase', amount: 1000, direction: 'debit');
    await addTransaction(
      id: 'prior',
      amount: 700,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-link', from: 'prior', to: 'purchase');
    await addTransaction(
      id: 'exact',
      amount: 300,
      direction: 'credit',
      date: refundDate,
    );
    await addTransaction(
      id: 'excess',
      amount: 301,
      direction: 'credit',
      date: refundDate,
    );

    final exact = await repository.previewForRefund('exact');
    final excess = await repository.previewForRefund('excess');

    expect(exact.status, RefundLinkPreviewStatus.ready);
    expect(exact.candidates.single.remainingRefundableAmount, 300);
    expect(excess.status, RefundLinkPreviewStatus.blocked);
    expect(excess.blockReason, RefundLinkPreviewBlockReason.overCap);
    expect(excess.candidates.single.remainingRefundableAmount, 300);
  });

  test('returns every candidate for a complete-reference ambiguity', () async {
    await addTransaction(
      id: 'purchase-b',
      amount: 900,
      direction: 'debit',
      date: purchaseDate.add(const Duration(days: 1)),
    );
    await addTransaction(id: 'purchase-a', amount: 800, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 100,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.ambiguous);
    expect(
      preview.candidates.map((row) => row.originalTransactionId),
      ['purchase-a', 'purchase-b'],
    );
  });

  test('uses exact six-place decimal arithmetic for accumulated adjustments',
      () async {
    await addTransaction(id: 'purchase', amount: 1, direction: 'debit');
    await addTransaction(
      id: 'prior-a',
      amount: 0.1,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 3)),
    );
    await addTransaction(
      id: 'prior-b',
      amount: 0.2,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-a-link', from: 'prior-a', to: 'purchase');
    await addLink(id: 'prior-b-link', from: 'prior-b', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 0.7,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.ready);
    expect(preview.candidates.single.existingAdjustmentAmount, 0.3);
    expect(preview.candidates.single.remainingRefundableAmount, 0.7);
  });

  test('rejects amounts with more than six decimal places explicitly',
      () async {
    await addTransaction(id: 'purchase', amount: 1, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 0.0000001,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
    );
  });

  test('stops at the indexed-reference candidate safety limit', () async {
    for (var index = 0; index < 400; index++) {
      await addTransaction(
        id: 'purchase-$index',
        amount: 100,
        direction: 'debit',
      );
    }
    await addTransaction(
      id: 'refund',
      amount: 10,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.lookupLimitExceeded,
    );
    expect(preview.candidates, isEmpty);
  });

  test('isolates existing refund arithmetic per ambiguous purchase', () async {
    await addTransaction(id: 'purchase-a', amount: 1000, direction: 'debit');
    await addTransaction(id: 'purchase-b', amount: 2000, direction: 'debit');
    await addTransaction(
      id: 'prior-a',
      amount: 100,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addTransaction(
      id: 'prior-b',
      amount: 200,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 1)),
    );
    await addLink(id: 'prior-a-link', from: 'prior-a', to: 'purchase-a');
    await addLink(id: 'prior-b-link', from: 'prior-b', to: 'purchase-b');
    await addTransaction(
      id: 'refund',
      amount: 50,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.ambiguous);
    expect(
      preview.candidates.map((candidate) => candidate.existingAdjustmentAmount),
      [100, 200],
    );
  });

  test('uses complete indexed raw references and has no arbitrary date window',
      () async {
    await addTransaction(
      id: 'old-purchase',
      amount: 500,
      direction: 'debit',
      date: purchaseDate,
      refId: 'PAY-123456789-A',
    );
    await addTransaction(
      id: 'same-digits-different-ref',
      amount: 500,
      direction: 'debit',
      date: purchaseDate,
      refId: 'PAY-123456789-B',
    );
    await addTransaction(
      id: 'refund',
      amount: 200,
      direction: 'credit',
      date: refundDate,
      refId: 'PAY-123456789-A',
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.ready);
    expect(preview.candidates.single.originalTransactionId, 'old-purchase');
  });

  test(
      'rejects missing rows, non-credit, missing reference, and invalid amount',
      () async {
    await addTransaction(id: 'debit', amount: 200, direction: 'debit');
    await addTransaction(
      id: 'no-reference',
      amount: 10,
      direction: 'credit',
      refId: null,
      date: refundDate,
    );
    await addTransaction(
      id: 'zero-credit',
      amount: 0,
      direction: 'credit',
      date: refundDate,
    );

    final missing = await repository.previewForRefund('missing');
    final wrongDirection = await repository.previewForRefund('debit');
    final noReference = await repository.previewForRefund('no-reference');
    final invalidAmount = await repository.previewForRefund('zero-credit');

    expect(missing.status, RefundLinkPreviewStatus.missingRefund);
    expect(
      wrongDirection.blockReason,
      RefundLinkPreviewBlockReason.invalidRefund,
    );
    expect(
      noReference.blockReason,
      RefundLinkPreviewBlockReason.missingExactReference,
    );
    expect(
      invalidAmount.blockReason,
      RefundLinkPreviewBlockReason.invalidRefund,
    );
  });

  test('excludes ineligible, non-spending, future, and other-currency debits',
      () async {
    await addTransaction(
      id: 'deleted',
      amount: 100,
      direction: 'debit',
      isDeleted: true,
    );
    await addTransaction(
      id: 'not-transaction',
      amount: 100,
      direction: 'debit',
      isNotTransaction: true,
    );
    await addTransaction(
      id: 'analytics-excluded',
      amount: 100,
      direction: 'debit',
      isAnalyticsExcluded: true,
    );
    await addTransaction(
      id: 'duplicate',
      amount: 100,
      direction: 'debit',
      duplicateOfTxnId: 'deleted',
    );
    await addTransaction(
      id: 'owned-transfer',
      amount: 100,
      direction: 'debit',
      ownedTransferId: 'transfer',
    );
    await addTransaction(
      id: 'pending',
      amount: 100,
      direction: 'debit',
      lifecycleState: 'pending',
    );
    await addTransaction(
      id: 'income-category',
      amount: 100,
      direction: 'debit',
      categoryId: 'income',
    );
    await addTransaction(
      id: 'future',
      amount: 100,
      direction: 'debit',
      date: refundDate.add(const Duration(days: 1)),
    );
    await addTransaction(
      id: 'usd',
      amount: 100,
      direction: 'debit',
      currencyCode: 'USD',
      currencySymbol: '\$',
    );
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.noMatch);
    expect(preview.candidates, isEmpty);
  });

  test('keeps ambiguous symbols and unknown currency buckets separate',
      () async {
    await addTransaction(
      id: 'usd',
      amount: 100,
      direction: 'debit',
      currencyCode: 'USD',
      currencySymbol: '\$',
    );
    await addTransaction(
      id: 'bare-dollar',
      amount: 100,
      direction: 'debit',
      currencyCode: null,
      currencySymbol: '\$',
    );
    await addTransaction(
      id: 'unknown',
      amount: 100,
      direction: 'debit',
      currencyCode: null,
      currencySymbol: null,
    );
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
      currencyCode: null,
      currencySymbol: '\$',
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.ready);
    expect(
      preview.candidates.map((candidate) => candidate.originalTransactionId),
      ['bare-dollar'],
    );
  });

  test('shows an already-linked refund once with pair arithmetic', () async {
    await addTransaction(id: 'purchase', amount: 1000, direction: 'debit');
    await addTransaction(
      id: 'prior',
      amount: 200,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-link', from: 'prior', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 300,
      direction: 'credit',
      date: refundDate,
    );
    await addLink(id: 'refund-link', from: 'refund', to: 'purchase');

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(preview.blockReason, RefundLinkPreviewBlockReason.alreadyLinked);
    expect(preview.candidates, hasLength(1));
    expect(preview.candidates.single.existingAdjustmentAmount, 500);
    expect(preview.candidates.single.proposedRefundAmount, 0);
    expect(preview.candidates.single.remainingRefundableAmount, 500);
  });

  test('rejects a refund source row already marked as a duplicate', () async {
    await addTransaction(id: 'purchase', amount: 100, direction: 'debit');
    await addTransaction(
      id: 'duplicate-refund-source',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
      duplicateOfTxnId: 'duplicate-refund-source',
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(preview.blockReason, RefundLinkPreviewBlockReason.invalidRefund);
  });

  test('blocks an adjustment credit with a competing echo classification',
      () async {
    await addTransaction(id: 'purchase', amount: 1000, direction: 'debit');
    await addTransaction(
      id: 'prior',
      amount: 100,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-link', from: 'prior', to: 'purchase');
    await addLink(
      id: 'competing-echo',
      from: 'prior',
      to: 'purchase',
      type: 'echo',
    );
    await addTransaction(
      id: 'refund',
      amount: 100,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );
  });

  test('rejects reversed-direction, duplicate, and over-cap existing links',
      () async {
    await addTransaction(id: 'purchase', amount: 100, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );
    await addLink(id: 'wrong-way', from: 'purchase', to: 'refund');
    final wrongWay = await repository.previewForRefund('refund');
    expect(
      wrongWay.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );

    await database.delete(database.transactionLinks).go();
    await addTransaction(
      id: 'duplicate-credit',
      amount: 30,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 1)),
    );
    await addLink(
      id: 'duplicate-link-1',
      from: 'duplicate-credit',
      to: 'purchase',
    );
    await addLink(
      id: 'duplicate-link-2',
      from: 'duplicate-credit',
      to: 'purchase',
    );
    final duplicate = await repository.previewForRefund('refund');
    expect(
      duplicate.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );

    await database.delete(database.transactionLinks).go();
    await addTransaction(
      id: 'prior-a',
      amount: 60,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addTransaction(
      id: 'prior-b',
      amount: 60,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 1)),
    );
    await addLink(id: 'prior-a-link', from: 'prior-a', to: 'purchase');
    await addLink(id: 'prior-b-link', from: 'prior-b', to: 'purchase');
    final overCap = await repository.previewForRefund('refund');
    expect(
      overCap.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );
  });

  test('rejects a zero-valued credit in existing adjustment links', () async {
    await addTransaction(id: 'purchase', amount: 100, direction: 'debit');
    await addTransaction(
      id: 'zero-credit',
      amount: 0,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 1)),
    );
    await addLink(id: 'zero-link', from: 'zero-credit', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 10,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );
  });

  test('blocks one refund credit linked to two different purchases', () async {
    await addTransaction(id: 'purchase-a', amount: 100, direction: 'debit');
    await addTransaction(id: 'purchase-b', amount: 200, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );
    await addLink(id: 'refund-a', from: 'refund', to: 'purchase-a');
    await addLink(id: 'refund-b', from: 'refund', to: 'purchase-b');

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );
    expect(preview.candidates, isEmpty);
  });

  test('bounds links touching an already-linked refund', () async {
    await addTransaction(id: 'purchase', amount: 100, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );
    await database.batch((batch) {
      batch.insertAll(
        database.transactionLinks,
        List.generate(
          2001,
          (index) => TransactionLinksCompanion.insert(
            id: 'link-$index',
            fromTxnId: 'refund',
            toTxnId: 'purchase',
            linkType: 'refunds',
            basis: 'bounded_fixture',
            createdAt: refundDate.millisecondsSinceEpoch,
          ),
        ),
      );
    });

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.lookupLimitExceeded,
    );
  });

  test('blocks adjustments posted before their original purchase', () async {
    await addTransaction(id: 'purchase', amount: 100, direction: 'debit');
    await addTransaction(
      id: 'prior-refund',
      amount: 20,
      direction: 'credit',
      date: purchaseDate.subtract(const Duration(days: 1)),
    );
    await addLink(id: 'prior-link', from: 'prior-refund', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 20,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.invalidExistingLinks,
    );
  });

  test('blocks already-linked source rows with unsupported precision',
      () async {
    await addTransaction(id: 'purchase', amount: 1, direction: 'debit');
    await addTransaction(
      id: 'prior',
      amount: 0.0000001,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-link', from: 'prior', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 0.1,
      direction: 'credit',
      date: refundDate,
    );
    await addLink(id: 'refund-link', from: 'refund', to: 'purchase');

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
    );
  });

  test('rejects arithmetic that cannot round-trip through source doubles',
      () async {
    await addTransaction(
      id: 'purchase',
      amount: 1000000000000000000,
      direction: 'debit',
    );
    await addTransaction(
      id: 'prior',
      amount: 0.1,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(id: 'prior-link', from: 'prior', to: 'purchase');
    await addTransaction(
      id: 'refund',
      amount: 0.1,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.status, RefundLinkPreviewStatus.blocked);
    expect(
      preview.blockReason,
      RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
    );
  });

  test('a reversal contributes to the same cap and must equal purchase amount',
      () async {
    await addTransaction(id: 'purchase', amount: 1000, direction: 'debit');
    await addTransaction(
      id: 'reversal',
      amount: 1000,
      direction: 'credit',
      date: refundDate.subtract(const Duration(days: 2)),
    );
    await addLink(
      id: 'reversal-link',
      from: 'reversal',
      to: 'purchase',
      type: 'reverses',
    );
    await addTransaction(
      id: 'refund',
      amount: 1,
      direction: 'credit',
      date: refundDate,
    );

    final preview = await repository.previewForRefund('refund');

    expect(preview.blockReason, RefundLinkPreviewBlockReason.overCap);
    expect(preview.candidates.single.existingAdjustmentAmount, 1000);
    expect(preview.candidates.single.remainingRefundableAmount, 0);
  });

  test('reopens from persisted rows and recomputes after source changes',
      () async {
    await database.close();
    persistentTestDirectory = await Directory.systemTemp.createTemp(
      'paisa-refund-preview-',
    );
    final path = '${persistentTestDirectory!.path}/preview.sqlite';
    database = AppDatabase(NativeDatabase(File(path)));
    repository = RefundLinkPreviewRepository(database);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'spend',
            name: 'Spend',
            icon: 'basket',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await addTransaction(id: 'purchase', amount: 1000, direction: 'debit');
    await addTransaction(
      id: 'refund',
      amount: 200,
      direction: 'credit',
      date: refundDate,
    );
    expect(
      (await repository.previewForRefund('refund')).status,
      RefundLinkPreviewStatus.ready,
    );
    await database.close();

    database = AppDatabase(NativeDatabase(File(path)));
    repository = RefundLinkPreviewRepository(database);
    final reopened = await repository.previewForRefund('refund');
    expect(reopened.status, RefundLinkPreviewStatus.ready);
    expect(reopened.candidates.single.remainingRefundableAmount, 1000);

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('purchase')))
        .write(const TransactionsCompanion(amount: Value(150)));
    final refreshed = await repository.previewForRefund('refund');
    expect(refreshed.status, RefundLinkPreviewStatus.blocked);
    expect(refreshed.blockReason, RefundLinkPreviewBlockReason.overCap);
  });
}
