import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

// Captures the last pushed token in state so tests can read it and invoke undo.
class _FakeUndoController extends UndoController {
  @override
  void pushUndo(UndoToken token) => state = token;
}

Future<AppDatabase> _seedDb() async {
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
  await db.into(db.merchants).insert(
        MerchantsCompanion.insert(
          id: 'm_swiggy',
          canonicalName: 'Swiggy',
          firstSeen: now,
          lastSeen: now,
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
          merchantId: const Value('m_swiggy'),
          merchantRaw: const Value('Swiggy'),
          refId: const Value('REF123'),
          counterpartyVpa: const Value('swiggy@icici'),
          balanceAfter: const Value(12500.0),
          categoryId: const Value('food_cat'),
          parseSource: 'template',
          confidenceJson: '{"parser":{"c":0.74,"src":"template"}}',
          createdAt: now,
          updatedAt: now,
        ),
      );
  return db;
}

const _foodCat = Category(
  id: 'food_cat',
  name: 'Food & Dining',
  icon: 'food',
  isSpending: true,
  sortOrder: 1,
  isUserCreated: false,
);
const _shoppingCat = Category(
  id: 'shopping_cat',
  name: 'Shopping',
  icon: 'shopping_cart',
  isSpending: true,
  sortOrder: 2,
  isUserCreated: false,
);

Future<ProviderContainer> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
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
        categoryListProvider.overrideWith(
          (ref) => Stream.value([_foodCat, _shoppingCat]),
        ),
        suggestedCategoriesProvider.overrideWith(
          (ref, _) async => ['shopping_cat'],
        ),
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
            home: const TransactionDetailScreen(txnId: 'txn_001'),
          );
        },
      ),
    ),
  );

  // FutureProvider (appDatabaseProvider) → StreamProvider chain needs time.
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  return container;
}

Future<Transaction> _fetchTxn(AppDatabase db) =>
    (db.select(db.transactions)..where((t) => t.id.equals('txn_001')))
        .getSingle();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T-159a — _selectCategoryDirectly', () {
    testWidgets(
        'tapping a non-current chip updates DB category and pushes undo token',
        (tester) async {
      final db = await _seedDb();
      final container = await _pumpDetail(tester, db);

      // The 'Shopping' chip is visible because suggestedCategoriesProvider
      // returns ['shopping_cat'] and it is not the current category.
      expect(find.text('Shopping'), findsOneWidget);

      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      // DB category changed.
      final txn = await _fetchTxn(db);
      expect(txn.categoryId, equals('shopping_cat'));

      // Undo token was pushed.
      final token = container.read(undoControllerProvider);
      expect(token, isNotNull);
      expect(token!.message, contains('Shopping'));

      await db.close();
    });

    testWidgets('undo reverts the DB category change', (tester) async {
      final db = await _seedDb();
      final container = await _pumpDetail(tester, db);

      await tester.tap(find.text('Shopping'));
      await tester.pumpAndSettle();

      final token = container.read(undoControllerProvider);
      expect(token, isNotNull);

      // Execute the undo action.
      await token!.undoAction();
      await tester.pumpAndSettle();

      final txn = await _fetchTxn(db);
      expect(txn.categoryId, equals('food_cat'));

      await db.close();
    });
  });

  group('T-159a — _changeCategory', () {
    testWidgets(
        'More chip → picker → scope → updates DB category and pushes undo token',
        (tester) async {
      final db = await _seedDb();
      final container = await _pumpDetail(tester, db);

      // Tap the 'CATEGORY' label — it's covered by the InkWell(onTap:
      // _changeCategory) that wraps the entire row, and sits above the
      // horizontal chip scroll (which may overflow the viewport).
      expect(find.text('CATEGORY'), findsOneWidget);
      await tester.tap(find.text('CATEGORY'));
      await tester.pumpAndSettle();

      // CategoryPickerSheet is now open. Use the ListTile finder to pick the
      // picker row rather than the background chip (both show 'Shopping').
      expect(find.widgetWithText(ListTile, 'Shopping'), findsWidgets);
      await tester.tap(find.widgetWithText(ListTile, 'Shopping').first);
      await tester.pumpAndSettle();

      // CategoryScopeSelectionSheet is now open. Tap 'This transaction only'.
      expect(find.text('This transaction only'), findsOneWidget);
      await tester.tap(find.text('This transaction only'));
      await tester.pumpAndSettle();

      // DB category changed.
      final txn = await _fetchTxn(db);
      expect(txn.categoryId, equals('shopping_cat'));

      // Undo token was pushed.
      final token = container.read(undoControllerProvider);
      expect(token, isNotNull);
      expect(token!.message, contains('Shopping'));

      await db.close();
    });

    testWidgets('undo after _changeCategory reverts the DB category',
        (tester) async {
      final db = await _seedDb();
      final container = await _pumpDetail(tester, db);

      await tester.tap(find.text('CATEGORY'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Shopping').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('This transaction only'));
      await tester.pumpAndSettle();

      final token = container.read(undoControllerProvider);
      await token!.undoAction();
      await tester.pumpAndSettle();

      final txn = await _fetchTxn(db);
      expect(txn.categoryId, equals('food_cat'));

      await db.close();
    });
  });
}
