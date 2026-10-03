import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/currency_repair_providers.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDetail(
    WidgetTester tester,
    TransactionDetail detail, {
    double textScale = 1,
    Size viewport = const Size(402, 874),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailProvider(detail.txn.id)
              .overrideWith((ref) => Stream.value(detail)),
          suggestedCategoriesProvider(detail.txn.id)
              .overrideWith((ref) => Future.value(['travel', 'utilities'])),
          sourceCurrencyRepairPreviewProvider(detail.txn.id)
              .overrideWith((ref) async => null),
        ],
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: detail.txn.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom TransactionDetailScreen', () {
    final now = DateTime.utc(2026, 7, 6, 9);
    final testDetail = TransactionDetail(
      txn: Transaction(
        id: 'txn_101',
        ts: now.millisecondsSinceEpoch,
        amount: 449,
        direction: 'debit',
        channel: 'upi',
        categoryId: 'food_dining',
        merchantRaw: 'amazon',
        parseSource: 'template',
        confidenceJson: '{}',
        status: 'confirmed',
        isDeleted: false,
        isNotTransaction: false,
        isAnalyticsExcluded: false,
        lifecycleState: 'settled',
        createdAt: now,
        updatedAt: now,
      ),
      merchantName: 'amazon',
      categoryName: 'Food & Dining',
      parseConfidence: 0.98,
      confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
      isLowTrustParse: false,
    );

    testWidgets('renders transaction detail with category tile and hero amount',
        (tester) async {
      await pumpDetail(tester, testDetail);

      expect(find.text('Transaction Detail'), findsOneWidget);
      expect(find.text('amazon'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.byType(BloomCategoryTile), findsOneWidget);
      expect(find.byType(BloomAmount), findsOneWidget);
    });

    testWidgets(
        'T-200 presents one unified confirmation action with checked fields',
        (tester) async {
      final reviewDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          status: 'needs_review',
          currencyCode: const Value('INR'),
          currencySymbol: const Value('₹'),
        ),
        merchantName: 'amazon',
        categoryName: 'Food & Dining',
        parseConfidence: 0.62,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: true,
        rawSmsBody: 'Paid Rs 449 to amazon',
        canConfirmParse: true,
      );

      await pumpDetail(
        tester,
        reviewDetail,
        textScale: 2,
        viewport: const Size(320, 568),
      );
      final detailScreen = tester.element(
        find.byType(TransactionDetailScreen),
      );
      expect(MediaQuery.sizeOf(detailScreen), const Size(320, 568));
      expect(MediaQuery.textScalerOf(detailScreen).scale(10), 20);

      final confirmationLabels = [
        find.text('Confirm'),
        find.text('Confirm parsed details'),
        find.text('Confirm details'),
      ];
      final confirmationLabelCount = confirmationLabels.fold<int>(
        0,
        (count, finder) => count + tester.widgetList<Text>(finder).length,
      );
      expect(confirmationLabelCount, 1);
      expect(find.text('Confirm details'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Confirm parsed details'), findsNothing);
      expect(find.text('₹449.00'), findsOneWidget);
      expect(find.text('Debit'), findsOneWidget);
      expect(find.textContaining('amazon'), findsWidgets);
      expect(find.textContaining('Food & Dining'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-200 keeps unknown currency unlabeled as rupees',
        (tester) async {
      final unknownCurrencyDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(status: 'needs_review'),
        merchantName: 'amazon',
        categoryName: 'Food & Dining',
        parseConfidence: null,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: false,
      );

      await pumpDetail(tester, unknownCurrencyDetail);

      expect(find.text('Confirm details'), findsOneWidget);
      expect(find.textContaining('₹449'), findsNothing);
    });

    testWidgets('T-200 keeps confirmation visible and disabled while saving',
        (tester) async {
      final databaseNeverCompletes = Completer<AppDatabase>();
      final reviewTxn = testDetail.txn.copyWith(
        status: 'needs_review',
        currencyCode: const Value('INR'),
        currencySymbol: const Value('₹'),
      );
      final detail = TransactionDetail(
        txn: reviewTxn,
        merchantName: 'amazon',
        categoryName: 'Food & Dining',
        parseConfidence: 0.62,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: false,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider
              .overrideWith((ref) => databaseNeverCompletes.future),
          transactionDetailProvider(reviewTxn.id)
              .overrideWith((ref) => Stream.value(detail)),
          suggestedCategoriesProvider(reviewTxn.id)
              .overrideWith((ref) => Future.value(['travel'])),
          sourceCurrencyRepairPreviewProvider(reviewTxn.id)
              .overrideWith((ref) async => null),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: reviewTxn.id),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final label = find.text('Confirm details');
      expect(label, findsOneWidget);
      await tester.ensureVisible(label);
      await tester.tap(label);
      await tester.tap(label);
      await tester.pump();
      expect(label, findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: label,
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    });

    testWidgets('T-200 reports stale confirmation and allows a retry',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final reviewDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(status: 'needs_review'),
        merchantName: 'amazon',
        categoryName: 'Food & Dining',
        parseConfidence: 0.62,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: false,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          transactionRepositoryProvider(database)
              .overrideWithValue(_StaleConfirmationRepository(database)),
          transactionDetailProvider(reviewDetail.txn.id)
              .overrideWith((ref) => Stream.value(reviewDetail)),
          suggestedCategoriesProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => const <String>[]),
          sourceCurrencyRepairPreviewProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => null),
          categoryListProvider.overrideWith((ref) => Stream.value([])),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: reviewDetail.txn.id),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final label = find.text('Confirm details');
      await tester.ensureVisible(label);
      await tester.tap(label);
      await tester.pump();
      expect(
        find.textContaining('changed or is no longer eligible'),
        findsOneWidget,
      );
      final retryButton = tester.widget<FilledButton>(
        find.ancestor(
          of: label,
          matching: find.byType(FilledButton),
        ),
      );
      expect(retryButton.onPressed, isNotNull);

      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await database.close();
    });

    testWidgets('T-196 shows a copyable transaction details card',
        (tester) async {
      final detail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          counterpartyVpa: const Value('payzomato@hdfcbank'),
          refId: const Value('624512345678'),
        ),
        merchantName: 'Zomato',
        categoryName: 'Food & Dining',
        parseConfidence: 0.98,
        confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
        isLowTrustParse: false,
      );
      await pumpDetail(tester, detail);

      final card = find.text('TRANSACTION DETAILS');
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      expect(find.text('payzomato@hdfcbank'), findsOneWidget);
      expect(find.text('624512345678'), findsOneWidget);
      expect(find.byTooltip('Copy UPI ID / VPA'), findsOneWidget);
    });

    testWidgets(
        'T-177a confirms parsed SMS from detail and updates template trust only',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
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
      final timestamp = DateTime.utc(2026, 7, 6, 9);
      await database.into(database.rawSms).insert(
            RawSmsCompanion.insert(
              id: 'sms_confirm_177a',
              sender: 'XX-BANK',
              body: 'Paid Rs 449 to Swiggy',
              receivedAt: timestamp,
              purgeAfter: timestamp.add(const Duration(days: 30)),
            ),
          );
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'txn_confirm_177a',
              ts: timestamp.millisecondsSinceEpoch,
              amount: 449,
              direction: 'debit',
              channel: 'upi',
              categoryId: const Value('other'),
              merchantRaw: const Value('Swiggy'),
              parseSource: 'template',
              smsId: const Value('sms_confirm_177a'),
              confidenceJson:
                  '{"parser":{"c":0.74,"src":"template","template_id":"public_v1","provenance":"public"}}',
              evidenceJson: const Value(
                '[{"field":"amount","start":9,"end":12,"verbatim":"449","extractor":"regex"}]',
              ),
              status: 'needs_review',
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );

      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          suggestedCategoriesProvider('txn_confirm_177a')
              .overrideWith((ref) async => const <String>[]),
        ],
      );
      var containerDisposed = false;
      addTearDown(() {
        if (!containerDisposed) container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: 'txn_confirm_177a'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final confirmButton = find.text('Confirm details');
      expect(confirmButton, findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Confirm parsed details'), findsNothing);
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.tap(confirmButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final feedback = await database.select(database.feedback).get();
      expect(feedback, hasLength(1));
      expect(feedback.single.field, 'parse_verdict');
      expect(feedback.single.newValue, 'ok');
      expect(
        (await TemplateTrustLedger(database).load())
            .entries['public_v1']
            ?.confirmedParses,
        1,
      );
      final transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_confirm_177a')))
          .getSingle();
      expect(transaction.status, 'confirmed');
      expect(transaction.categoryId, 'other');
      expect(find.text('Confirm details'), findsNothing);
      expect(find.text('Details confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);

      container.dispose();
      containerDisposed = true;
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('T-193 previews, applies, and undoes retained INR evidence',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final timestamp = DateTime.now();
      const body = 'Paid Rs. 500 to Swiggy';
      final amountStart = body.indexOf('500');
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
      await database.into(database.rawSms).insert(
            RawSmsCompanion.insert(
              id: 'sms_repair_193',
              sender: 'XX-BANK',
              body: body,
              receivedAt: timestamp.subtract(const Duration(days: 1)),
              purgeAfter: timestamp.add(const Duration(days: 10)),
            ),
          );
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'txn_repair_193',
              ts: timestamp.millisecondsSinceEpoch,
              amount: 500,
              direction: 'debit',
              channel: 'upi',
              categoryId: const Value('food'),
              merchantRaw: const Value('Swiggy'),
              parseSource: 'template',
              smsId: const Value('sms_repair_193'),
              confidenceJson: '{}',
              evidenceJson: Value(
                '[{"field":"amount","start":$amountStart,"end":${amountStart + 3},"verbatim":"500","extractor":"template"}]',
              ),
              status: 'confirmed',
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );

      expect(
        await SourceCurrencyRepairService(database).preview('txn_repair_193'),
        isNotNull,
      );

      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          suggestedCategoriesProvider('txn_repair_193')
              .overrideWith((ref) async => const <String>[]),
        ],
      );
      var containerDisposed = false;
      addTearDown(() {
        if (!containerDisposed) container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: 'txn_repair_193'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 150));

      final semantics = tester.ensureSemantics();
      final reviewButton = find.byKey(const Key('reviewCurrencyRepair'));
      expect(reviewButton, findsOneWidget);
      expect(tester.getSize(reviewButton).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(reviewButton).label,
        'Review INR from SMS',
      );
      expect(
        tester
            .getSemantics(reviewButton)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.ensureVisible(reviewButton);
      await tester.tap(reviewButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Use INR from the original SMS?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('The retained message shows “Rs.”'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Apply INR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      var transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_repair_193')))
          .getSingle();
      expect(transaction.currencyCode, 'INR');
      expect(transaction.currencySymbol, '₹');
      expect(transaction.amount, 500);
      expect(transaction.categoryId, 'food');
      expect(transaction.status, 'confirmed');
      expect(find.byKey(const Key('reviewCurrencyRepair')), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_repair_193')))
          .getSingle();
      expect(transaction.currencyCode, isNull);
      expect(transaction.currencySymbol, isNull);
      expect(transaction.amount, 500);
      expect(transaction.categoryId, 'food');
      expect(transaction.status, 'confirmed');
      expect(tester.takeException(), isNull);
      semantics.dispose();

      container.dispose();
      containerDisposed = true;
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    });

    testWidgets('discloses technical details & raw SMS provenance when tapped',
        (tester) async {
      await pumpDetail(tester, testDetail);

      final techHeader = find.text('Technical details & SMS provenance');
      expect(techHeader, findsOneWidget);

      await tester.ensureVisible(techHeader);
      await tester.tap(techHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Review status: confirmed'), findsOneWidget);
      expect(find.textContaining('CONFIDENCE: 98%'), findsOneWidget);
    });

    testWidgets(
        'T-148a: category row is a >=48dp control with correct semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDetail(tester, testDetail);

      final inkWellFinder = find.ancestor(
        of: find.text('CATEGORY'),
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.height, greaterThanOrEqualTo(48.0));
      handle.dispose();
    });

    testWidgets(
        'T-148b: renders selected category chip in category hue and More chip',
        (tester) async {
      await pumpDetail(tester, testDetail);

      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget); // Selected chip
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets(
        'T-147a: renders retained source message as a first-class section',
        (tester) async {
      final retainedDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value('sms_001')),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Paid Rs 449 to Swiggy on A/c XX1234',
      );

      await pumpDetail(tester, retainedDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsOneWidget);
      expect(find.text('Paid Rs 449 to Swiggy on A/c XX1234'), findsOneWidget);
    });

    testWidgets('T-147a: renders missing-source copy without a retention claim',
        (tester) async {
      final purgedDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value('sms_002')),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: null,
      );

      await pumpDetail(tester, purgedDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsOneWidget);
      expect(
        find.text('Original message is not stored on this phone'),
        findsOneWidget,
      );
    });

    testWidgets(
        'T-147a: omits WHERE THIS CAME FROM section for manual entry rows',
        (tester) async {
      final manualDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value(null)),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: null,
      );

      await pumpDetail(tester, manualDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsNothing);
    });

    testWidgets(
        'T-147b: renders Parsed locally badge and parser name for template source',
        (tester) async {
      final templateDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_tmpl_147b',
          smsId: const Value('sms_001'),
          parseSource: 'template',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.99,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Paid Rs 449 to Swiggy on A/c XX1234',
      );

      await pumpDetail(tester, templateDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('Template match · 99%'), findsOneWidget);
    });

    testWidgets('T-167c provenance badge grows to fit 2x text', (tester) async {
      final templateDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_tmpl_large_text',
          smsId: const Value('sms_large_text'),
          parseSource: 'template',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.99,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Paid Rs 449 to Swiggy on A/c XX1234',
      );

      await pumpDetail(
        tester,
        templateDetail,
        textScale: 2,
        viewport: const Size(434, 964),
      );

      final badge = find.byKey(const ValueKey('parser_provenance_badge'));
      final label = find.text('Parsed locally');
      expect(badge, findsOneWidget);
      expect(
        tester.getRect(badge).height,
        greaterThanOrEqualTo(tester.getRect(label).height),
      );
      expect(find.text('Template match · 99%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'T-147b: renders Parsed locally badge and parser name for generic source',
        (tester) async {
      final genericDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_gen_147b',
          smsId: const Value('sms_002'),
          parseSource: 'generic',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.85,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Rs 100 paid to Cafe',
      );

      await pumpDetail(tester, genericDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('Pattern match · 85%'), findsOneWidget);
    });

    testWidgets(
        'T-147b: renders Parsed locally badge and parser name for LLM source',
        (tester) async {
      final llmDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_llm_147b',
          smsId: const Value('sms_003'),
          parseSource: 'llm',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.92,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Debited Rs 500 at Uber',
      );

      await pumpDetail(tester, llmDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('AI model · 92%'), findsOneWidget);
    });
  });
}

class _StaleConfirmationRepository extends TransactionRepository {
  // The parent constructor exposes this as a private positional parameter.
  // ignore: use_super_parameters
  _StaleConfirmationRepository(AppDatabase database) : super(database);

  @override
  Future<ReviewDetailsConfirmationReceipt?> confirmReviewDetails({
    required String txnId,
    required Transaction observedTransaction,
    DateTime Function() clock = DateTime.now,
  }) async =>
      null;
}
