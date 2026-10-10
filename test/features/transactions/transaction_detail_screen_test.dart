import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/data/repositories/merchant_category_suggestion_repository.dart';
import 'package:paisatrack/data/repositories/payee_evidence_repository.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/data/repositories/recurring_override_repository.dart';
import 'package:paisatrack/data/repositories/transaction_sms_repository.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/currency_repair_providers.dart';
import 'package:paisatrack/features/transactions/merchant_category_suggestion_provider.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import '../../support/drift_widget_teardown.dart';

class _RecordingUndoController extends UndoController {
  @override
  void pushUndo(UndoToken token) => state = token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> pumpDetail(
    WidgetTester tester,
    TransactionDetail detail, {
    double textScale = 1,
    Size viewport = const Size(402, 874),
    MerchantCategorySuggestion? memorySuggestion,
    AppDatabase? database,
    Future<AppDatabase>? databaseFuture,
    bool enableMemorySuggestions = false,
    Stream<TransactionDetail?>? detailStream,
    bool useRealDetailProvider = false,
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
          if (databaseFuture != null)
            appDatabaseProvider.overrideWith((ref) => databaseFuture),
          if (databaseFuture == null && database != null)
            appDatabaseProvider.overrideWith((ref) async => database),
          if (enableMemorySuggestions)
            categoryMemorySuggestionsEnabledProvider.overrideWith(
              (ref) => true,
            ),
          if (database != null || databaseFuture != null)
            categoryListProvider.overrideWith(
              (ref) => Stream.value(const [
                Category(
                  id: 'food_dining',
                  name: 'Food & Dining',
                  icon: 'restaurant',
                  isSpending: true,
                  sortOrder: 1,
                  isUserCreated: false,
                ),
                Category(
                  id: 'travel',
                  name: 'Travel',
                  icon: 'train',
                  isSpending: true,
                  sortOrder: 2,
                  isUserCreated: false,
                ),
              ]),
            ),
          if (database != null || databaseFuture != null)
            undoControllerProvider.overrideWith(_RecordingUndoController.new),
          if (!useRealDetailProvider)
            transactionDetailProvider(detail.txn.id)
                .overrideWith((ref) => detailStream ?? Stream.value(detail)),
          suggestedCategoriesProvider(detail.txn.id)
              .overrideWith((ref) => Future.value(['travel', 'utilities'])),
          transactionSmsMessagesProvider(detail.txn.id)
              .overrideWith((ref) async => const []),
          transactionRecurringOverrideProvider(detail.txn.id).overrideWith(
            (ref) => Stream.value(RecurringOverride.automatic),
          ),
          transactionDetectedRecurringProvider(detail.txn.id)
              .overrideWith((ref) async => false),
          sourceCurrencyRepairPreviewProvider(detail.txn.id)
              .overrideWith((ref) async => null),
          if (memorySuggestion != null)
            merchantCategorySuggestionProvider(detail.txn.id).overrideWith(
              (ref) async => memorySuggestion,
            ),
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
    return ProviderScope.containerOf(
      tester.element(find.byType(TransactionDetailScreen)),
    );
  }

  Future<AppDatabase> seedCategorySuggestionDatabase({
    int explicitOutcomes = 2,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 7, 6, 9);
    for (final category in const [
      Category(
        id: 'food_dining',
        name: 'Food & Dining',
        icon: 'restaurant',
        isSpending: true,
        sortOrder: 1,
        isUserCreated: false,
      ),
      Category(
        id: 'travel',
        name: 'Travel',
        icon: 'train',
        isSpending: true,
        sortOrder: 2,
        isUserCreated: false,
      ),
    ]) {
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: category.id,
              name: category.name,
              icon: category.icon,
              isSpending: category.isSpending,
              sortOrder: category.sortOrder,
              isUserCreated: category.isUserCreated,
            ),
          );
    }

    Future<void> addTransaction(String id, String categoryId) async {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: now.millisecondsSinceEpoch,
              amount: 449,
              direction: 'debit',
              channel: 'upi',
              merchantRaw: const Value('amazon'),
              categoryId: Value(categoryId),
              parseSource: 'template',
              confidenceJson: id == 'txn_101'
                  ? '{}'
                  : '{"category":{"c":0.8,"src":"seed"}}',
              status: id == 'txn_101' ? 'needs_review' : 'confirmed',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await PayeeEvidenceRepository(database).replaceForTransaction(
        transactionId: id,
        merchantRaw: 'amazon',
      );
    }

    await addTransaction('txn_101', 'food_dining');
    for (var index = 0; index < explicitOutcomes; index++) {
      final id = 'history_$index';
      await addTransaction(id, 'travel');
      await database.into(database.feedback).insert(
            FeedbackCompanion.insert(
              id: 'confirm_$id',
              txnId: id,
              field: 'status',
              oldValue: const Value('needs_review'),
              newValue: const Value('confirmed'),
              context: 'activity_confirm',
              createdAt: now.add(Duration(seconds: index + 1)),
            ),
          );
    }
    return database;
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
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
      expect(
        find.byKey(const ValueKey('merchant-category-suggestion')),
        findsNothing,
      );
    });

    testWidgets('shows the gated prior-choice suggestion on transaction detail',
        (tester) async {
      await pumpDetail(
        tester,
        testDetail,
        memorySuggestion: const MerchantCategorySuggestion(
          categoryId: 'travel',
          categoryName: 'Travel',
          supportingTransactionCount: 2,
        ),
      );

      expect(find.text('Based on your past category choices'), findsOneWidget);
      expect(find.text('Use Travel'), findsOneWidget);
      expect(find.textContaining('2 prior transactions'), findsOneWidget);
    });

    testWidgets('removes a stale suggestion after an explicit detail edit',
        (tester) async {
      final database = await seedCategorySuggestionDatabase();
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          categoryListProvider.overrideWith(
            (ref) => Stream.value(const [
              Category(
                id: 'food_dining',
                name: 'Food & Dining',
                icon: 'restaurant',
                isSpending: true,
                sortOrder: 1,
                isUserCreated: false,
              ),
              Category(
                id: 'travel',
                name: 'Travel',
                icon: 'train',
                isSpending: true,
                sortOrder: 2,
                isUserCreated: false,
              ),
            ]),
          ),
          undoControllerProvider.overrideWith(_RecordingUndoController.new),
          suggestedCategoriesProvider('txn_101')
              .overrideWith((ref) async => const <String>[]),
          sourceCurrencyRepairPreviewProvider('txn_101')
              .overrideWith((ref) async => null),
          categoryMemorySuggestionsEnabledProvider.overrideWith((ref) => true),
        ],
      );
      var containerDisposed = false;
      var databaseClosed = false;
      addTearDown(() async {
        if (!containerDisposed) {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          containerDisposed = true;
          await pumpDriftFrames(tester);
        }
        if (!databaseClosed) await database.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view),
            child: const MaterialApp(
              home: BloomUndoToastHost(
                child: TransactionDetailScreen(txnId: 'txn_101'),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      expect(find.text('Based on your past category choices'), findsOneWidget);

      await TransactionRepository(database).updateWithFeedback(
        txnId: 'txn_101',
        categoryId: const Value('travel'),
        context: 'detail_chip_edit',
      );
      await pumpFrames(tester);

      expect(find.text('Based on your past category choices'), findsNothing);
      expect(find.text('Travel'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      containerDisposed = true;
      await pumpDriftFrames(tester);
      await unmountAndCloseDatabase(tester, database);
      databaseClosed = true;
    });

    testWidgets('accept changes only category and receipt Undo restores it',
        (tester) async {
      final database = await seedCategorySuggestionDatabase();
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          categoryListProvider.overrideWith(
            (ref) => Stream.value(const [
              Category(
                id: 'food_dining',
                name: 'Food & Dining',
                icon: 'restaurant',
                isSpending: true,
                sortOrder: 1,
                isUserCreated: false,
              ),
              Category(
                id: 'travel',
                name: 'Travel',
                icon: 'train',
                isSpending: true,
                sortOrder: 2,
                isUserCreated: false,
              ),
            ]),
          ),
          undoControllerProvider.overrideWith(_RecordingUndoController.new),
          suggestedCategoriesProvider('txn_101')
              .overrideWith((ref) async => const <String>[]),
          sourceCurrencyRepairPreviewProvider('txn_101')
              .overrideWith((ref) async => null),
          categoryMemorySuggestionsEnabledProvider.overrideWith((ref) => true),
        ],
      );
      var containerDisposed = false;
      var databaseClosed = false;
      addTearDown(() async {
        if (!containerDisposed) {
          await tester.pumpWidget(const SizedBox.shrink());
          container.dispose();
          containerDisposed = true;
          await pumpDriftFrames(tester);
        }
        if (!databaseClosed) await database.close();
      });
      addTearDown(() {
        if (!containerDisposed) container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view),
            child: const MaterialApp(
              home: BloomUndoToastHost(
                child: TransactionDetailScreen(txnId: 'txn_101'),
              ),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      final semantics = tester.ensureSemantics();

      expect(find.text('Use Travel'), findsOneWidget);
      final noteField = find.byType(TextField);
      expect(noteField, findsOneWidget);
      await tester.enterText(noteField, 'Unsaved note draft');
      await tester.ensureVisible(find.text('Use Travel'));
      await tester.tap(find.text('Use Travel'));
      await pumpFrames(tester);

      var transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_101')))
          .getSingle();
      expect(transaction.categoryId, 'travel');
      expect(transaction.status, 'needs_review');
      expect(transaction.amount, 449);
      expect(transaction.direction, 'debit');
      expect(transaction.confidenceJson, '{}');
      expect(find.text('Travel'), findsWidgets);
      expect(
        await (database.select(database.feedback)
              ..where(
                (row) =>
                    row.txnId.equals('txn_101') &
                    row.field.equals('category_id') &
                    row.context.equals('merchant_suggestion_accept'),
              ))
            .get(),
        hasLength(1),
      );
      expect(container.read(undoControllerProvider), isNotNull);

      await container.read(undoControllerProvider)!.undoAction();
      await pumpFrames(tester);
      transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_101')))
          .getSingle();
      expect(transaction.categoryId, 'food_dining');
      expect(transaction.status, 'needs_review');
      expect(find.text('Food & Dining'), findsWidgets);
      expect(
        tester.widget<TextField>(noteField).controller?.text,
        'Unsaved note draft',
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Category, Food & Dining, double tap to change'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<BloomCategoryTile>(find.byType(BloomCategoryTile).first)
            .categoryId,
        'food_dining',
      );
      expect(
        await (database.select(database.feedback)
              ..where((row) => row.txnId.equals('txn_101')))
            .get(),
        isEmpty,
      );

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      containerDisposed = true;
      await pumpDriftFrames(tester);
      await unmountAndCloseDatabase(tester, database);
      databaseClosed = true;
    });

    testWidgets('stale suggestion acceptance shows a no-op message',
        (tester) async {
      final database = await seedCategorySuggestionDatabase(
        explicitOutcomes: 1,
      );
      final storedTarget = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_101')))
          .getSingle();
      final pendingDetail = TransactionDetail(
        txn: storedTarget,
        merchantName: 'amazon',
        categoryName: 'Food & Dining',
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: false,
      );
      await pumpDetail(
        tester,
        pendingDetail,
        database: database,
        memorySuggestion: const MerchantCategorySuggestion(
          categoryId: 'travel',
          categoryName: 'Travel',
          supportingTransactionCount: 2,
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Use Travel'), findsOneWidget);
      final noteField = find.byType(TextField);
      await tester.enterText(noteField, 'Unsaved note draft');
      await tester.ensureVisible(find.text('Use Travel'));
      await tester.tap(find.text('Use Travel'));
      await pumpFrames(tester);

      expect(
        find.text('This suggestion changed. Refresh and try again.'),
        findsOneWidget,
      );
      final transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_101')))
          .getSingle();
      expect(transaction.categoryId, 'food_dining');
      expect(
        tester.widget<TextField>(noteField).controller?.text,
        'Unsaved note draft',
      );
      expect(
        await (database.select(database.feedback)
              ..where((row) => row.txnId.equals('txn_101')))
            .get(),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDriftFrames(tester);
      await unmountAndCloseDatabase(tester, database);
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
      expect(find.text('₹449.00'), findsWidgets);
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

    testWidgets('confirming details shows exactly one toast (owner report)',
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
              .overrideWithValue(_ConfirmingRepository(database)),
          transactionDetailProvider(reviewDetail.txn.id)
              .overrideWith((ref) => Stream.value(reviewDetail)),
          suggestedCategoriesProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => const <String>[]),
          sourceCurrencyRepairPreviewProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => null),
          categoryListProvider.overrideWith((ref) => Stream.value([])),
          // Live Drift watches never settle under the widget-test clock.
          transactionSmsMessagesProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => const []),
          transactionRecurringOverrideProvider(reviewDetail.txn.id)
              .overrideWith(
            (ref) => Stream.value(RecurringOverride.automatic),
          ),
          transactionDetectedRecurringProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => false),
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
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Transaction details confirmed'), findsOneWidget);

      container.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await database.close();
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
          // Live Drift watches never settle under the widget-test clock.
          transactionSmsMessagesProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => const []),
          transactionRecurringOverrideProvider(reviewDetail.txn.id)
              .overrideWith(
            (ref) => Stream.value(RecurringOverride.automatic),
          ),
          transactionDetectedRecurringProvider(reviewDetail.txn.id)
              .overrideWith((ref) async => false),
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

      final techHeader = find.text('Technical details');
      expect(techHeader, findsOneWidget);

      await tester.ensureVisible(techHeader);
      await tester.tap(techHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Review status'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
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

      expect(find.text('SOURCE SMS'), findsOneWidget);
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

      expect(find.text('SOURCE SMS'), findsOneWidget);
      expect(
        find.text('Source message not available'),
        findsOneWidget,
      );
    });

    testWidgets('T-147a: omits SOURCE SMS section for manual entry rows',
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

      expect(find.text('SOURCE SMS'), findsNothing);
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

class _ConfirmingRepository extends TransactionRepository {
  // The parent constructor exposes this as a private positional parameter.
  // ignore: use_super_parameters
  _ConfirmingRepository(AppDatabase database) : super(database);

  @override
  Future<ReviewDetailsConfirmationReceipt?> confirmReviewDetails({
    required String txnId,
    required Transaction observedTransaction,
    DateTime Function() clock = DateTime.now,
  }) async =>
      ReviewDetailsConfirmationReceipt(
        before: observedTransaction,
        after: observedTransaction.copyWith(status: 'confirmed'),
        createdParseConfirmation: null,
      );
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
