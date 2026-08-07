import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeUndoController extends UndoController {
  @override
  void pushUndo(UndoToken token) => state = token;
}

void main() {
  TransactionReviewItem reviewItem({
    required String id,
    required String displayName,
    required String counterpartyKey,
    String? categoryId,
  }) {
    return TransactionReviewItem(
      id: id,
      ts: DateTime.utc(2026, 7, 11, 10),
      amount: 100,
      direction: TransactionDirection.debit,
      displayName: displayName,
      categoryName: categoryId,
      categoryId: categoryId,
      categoryIcon: 'food',
      status: 'needs_review',
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<TransactionReviewItem> items,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
          categoryListProvider.overrideWith((ref) => Stream.value([])),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const BloomUndoToastHost(
            child: WeeklyReviewScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows Inbox Zero when review queue is empty', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('Inbox Zero!'), findsOneWidget);
  });

  testWidgets('renders top item in swipeable card stack', (tester) async {
    await pumpScreen(tester, [
      reviewItem(
        id: '1',
        displayName: 'Swiggy',
        counterpartyKey: 'raw:swiggy',
        categoryId: 'Food',
      ),
    ]);

    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T-159a — behavioral coverage for _confirmItem and _recategorizeItem
  // ---------------------------------------------------------------------------

  Future<AppDatabase> seedDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 7, 26);
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'food_cat',
            name: 'Food & Dining',
            icon: 'food',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'shopping_cat',
            name: 'Shopping',
            icon: 'shopping_cart',
            isSpending: true,
            sortOrder: 2,
            isUserCreated: false,
          ),
        );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_001',
            ts: now.millisecondsSinceEpoch,
            amount: 450.0,
            direction: 'debit',
            channel: 'UPI',
            status: 'needs_review',
            merchantRaw: const Value('Swiggy'),
            categoryId: const Value('food_cat'),
            parseSource: 'template',
            confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return db;
  }

  Future<ProviderContainer> pumpSortWithDb(
    WidgetTester tester,
    AppDatabase database,
    List<TransactionReviewItem> items,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
          categoryListProvider.overrideWith(
            (ref) => Stream.value([
              const Category(
                id: 'food_cat',
                name: 'Food & Dining',
                icon: 'food',
                isSpending: true,
                sortOrder: 1,
                isUserCreated: false,
              ),
              const Category(
                id: 'shopping_cat',
                name: 'Shopping',
                icon: 'shopping_cart',
                isSpending: true,
                sortOrder: 2,
                isUserCreated: false,
              ),
            ]),
          ),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
          undoControllerProvider.overrideWith(_FakeUndoController.new),
        ],
        child: Builder(
          builder: (ctx) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: const BloomUndoToastHost(
                child: WeeklyReviewScreen(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  group('T-159a — _confirmItem', () {
    // NOTE: _confirmItem calls repo.updateWithFeedback(status: 'confirmed'),
    // but updateWithFeedback's feedbackRows guard (line 527 of
    // transaction_repository.dart) silently skips the DB write when no
    // non-status fields change. These tests therefore characterize the
    // *current* UI behavior (item removed from queue, undo token pushed)
    // without asserting the DB write — see spawned task for the fix.

    testWidgets(
        'confirm button removes item from queue and pushes undo token',
        (tester) async {
      final db = await seedDb();
      final container = await pumpSortWithDb(
        tester,
        db,
        [
          reviewItem(
            id: 'txn_001',
            displayName: 'Swiggy',
            counterpartyKey: 'raw:swiggy',
            categoryId: 'food_cat',
          ),
        ],
      );

      expect(find.text('Swiggy'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Item removed from local queue — Inbox Zero view.
      expect(find.text('Inbox Zero!'), findsOneWidget);

      // Undo token pushed.
      final token = container.read(undoControllerProvider);
      expect(token, isNotNull);
      expect(token!.message, contains('confirmed'));

      await db.close();
    });

    testWidgets('undo after confirm re-inserts item into the queue',
        (tester) async {
      final db = await seedDb();
      final container = await pumpSortWithDb(
        tester,
        db,
        [
          reviewItem(
            id: 'txn_001',
            displayName: 'Swiggy',
            counterpartyKey: 'raw:swiggy',
            categoryId: 'food_cat',
          ),
        ],
      );

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Inbox Zero!'), findsOneWidget);

      final token = container.read(undoControllerProvider);
      await token!.undoAction();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Item re-inserted into _stableQueue.
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Inbox Zero!'), findsNothing);

      await db.close();
    });
  });

  group('T-159a — _recategorizeItem', () {
    testWidgets(
        'change-category button → picker → updates DB category and pushes undo token',
        (tester) async {
      final db = await seedDb();
      final container = await pumpSortWithDb(
        tester,
        db,
        [
          reviewItem(
            id: 'txn_001',
            displayName: 'Swiggy',
            counterpartyKey: 'raw:swiggy',
            categoryId: 'food_cat',
          ),
        ],
      );

      expect(find.text('Swiggy'), findsOneWidget);

      // Tap the gold change-category button.
      await tester.tap(find.byIcon(Icons.sell_outlined));
      await tester.pumpAndSettle();

      // CategoryPickerSheet is now open.
      expect(find.text('Shopping'), findsOneWidget);
      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      // DB category changed.
      final txn = await (db.select(db.transactions)
            ..where((t) => t.id.equals('txn_001')))
          .getSingle();
      expect(txn.categoryId, equals('shopping_cat'));

      // Undo token pushed.
      final token = container.read(undoControllerProvider);
      expect(token, isNotNull);
      expect(token!.message, contains('Shopping'));

      await db.close();
    });

    testWidgets('undo after _recategorizeItem reverts DB category',
        (tester) async {
      final db = await seedDb();
      final container = await pumpSortWithDb(
        tester,
        db,
        [
          reviewItem(
            id: 'txn_001',
            displayName: 'Swiggy',
            counterpartyKey: 'raw:swiggy',
            categoryId: 'food_cat',
          ),
        ],
      );

      await tester.tap(find.byIcon(Icons.sell_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      final token = container.read(undoControllerProvider);
      await token!.undoAction();
      await tester.pumpAndSettle();

      final txn = await (db.select(db.transactions)
            ..where((t) => t.id.equals('txn_001')))
          .getSingle();
      expect(txn.categoryId, equals('food_cat'));

      await db.close();
    });
  });
}
