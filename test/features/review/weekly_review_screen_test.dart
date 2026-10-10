import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/review/weekly_review_providers.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import '../../support/drift_widget_teardown.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeUndoController extends UndoController {
  @override
  void pushUndo(UndoToken token) => state = token;
}

class _InitialReviewViewNotifier extends ReviewViewNotifier {
  _InitialReviewViewNotifier(this.mode);

  final ReviewViewMode mode;

  @override
  ReviewViewState build() => ReviewViewState(viewMode: mode);
}

void main() {
  test('undo controller consumes a token after executing it once', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var calls = 0;
    final controller = container.read(undoControllerProvider.notifier);
    controller.pushUndo(
      UndoToken(
        id: 'undo_once',
        message: 'Undo once',
        undoAction: () async {
          calls++;
        },
      ),
    );

    expect(await controller.undo(), isTrue);
    expect(await controller.undo(), isFalse);
    expect(calls, 1);
  });

  TransactionReviewItem reviewItem({
    required String id,
    required String displayName,
    required String counterpartyKey,
    String? categoryId,
    String? counterpartyVpa,
    TransactionDirection direction = TransactionDirection.debit,
    String? currencyCode,
    String? currencySymbol,
    bool isLowTrustParse = false,
  }) {
    return TransactionReviewItem(
      id: id,
      ts: DateTime.utc(2026, 7, 11, 10),
      amount: 100,
      direction: direction,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      displayName: displayName,
      categoryName: categoryId,
      categoryId: categoryId,
      categoryIcon: 'food',
      status: 'needs_review',
      counterpartyVpa: counterpartyVpa,
      isLowTrustParse: isLowTrustParse,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<TransactionReviewItem> items, {
    Size size = const Size(402, 874),
    double textScale = 1,
    AppDatabase? database,
    ReviewViewMode? initialViewMode,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (database != null)
            appDatabaseProvider.overrideWith((ref) async => database),
          if (initialViewMode != null)
            reviewViewProvider.overrideWith(
              () => _InitialReviewViewNotifier(initialViewMode),
            ),
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
          categoryListProvider.overrideWith((ref) => Stream.value([])),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
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

  testWidgets('card view stays usable at 320dp and 2x text', (tester) async {
    await pumpScreen(
      tester,
      [
        reviewItem(
          id: 'narrow-card',
          displayName: 'Swiggy',
          counterpartyKey: 'raw:swiggy',
          categoryId: 'Food',
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
    );

    final screen = tester.element(find.byType(WeeklyReviewScreen));
    expect(MediaQuery.sizeOf(screen), const Size(320, 568));
    expect(MediaQuery.textScalerOf(screen).scale(10), 20);
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

  testWidgets('Review list header and row stay usable at 320dp and 2x text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    final database = AppDatabase(NativeDatabase.memory());
    var databaseClosed = false;
    addTearDown(() async {
      if (!databaseClosed) await unmountAndCloseDatabase(tester, database);
    });
    await pumpScreen(
      tester,
      [
        reviewItem(
          id: 'accessible-review',
          displayName: 'Swiggy',
          counterpartyKey: 'raw:swiggy',
          categoryId: 'Food',
        ),
        reviewItem(
          id: 'credit-review',
          displayName: 'Credit shop',
          counterpartyKey: 'raw:credit-shop',
          categoryId: 'Income',
          direction: TransactionDirection.credit,
          currencyCode: 'USD',
          currencySymbol: r'$',
          isLowTrustParse: true,
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
      database: database,
      initialViewMode: ReviewViewMode.list,
    );

    final screen = tester.element(find.byType(WeeklyReviewScreen));
    expect(MediaQuery.sizeOf(screen), const Size(320, 568));
    expect(MediaQuery.textScalerOf(screen).scale(10), 20);
    expect(tester.takeException(), isNull);

    final listView = find.bySemanticsLabel('List view');
    final modeData = tester.getSemantics(listView).getSemanticsData();
    expect(modeData.flagsCollection.isButton, isTrue);
    expect(modeData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(modeData.hint, contains('Switch to card view'));
    expect(tester.getSemantics(listView).rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(listView).rect.width, greaterThanOrEqualTo(48));
    final modeRect = tester.getRect(listView);
    expect(modeRect.height, greaterThanOrEqualTo(48));
    expect(modeRect.width, greaterThanOrEqualTo(48));

    await tester.scrollUntilVisible(find.text('Swiggy'), 100);
    final row = find.bySemanticsLabel(RegExp('Swiggy'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final rowData = tester.getSemantics(row).getSemanticsData();
    expect(rowData.label, contains('Food'));
    expect(rowData.label, contains('Expense'));
    expect(rowData.label, contains('-100.00 (currency unknown)'));
    expect(rowData.label, contains('Needs review'));
    expect(rowData.role, SemanticsRole.none);
    expect(rowData.hasAction(SemanticsAction.tap), isFalse);
    expect(tester.getSemantics(row).rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(row).rect.width, greaterThanOrEqualTo(48));
    expect(tester.getRect(row).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(row).width, greaterThanOrEqualTo(48));
    final rowNode = tester.getSemantics(row);
    final rowActions = rowData.customSemanticsActionIds!
        .map(CustomSemanticsAction.getAction)
        .map((action) => action!.label)
        .toSet();
    expect(rowActions, containsAll(['Keep', 'Change category', 'Skip']));
    final keepActionId = rowData.customSemanticsActionIds!.singleWhere(
      (id) => CustomSemanticsAction.getAction(id)?.label == 'Keep',
    );
    rowNode.owner!.performAction(
      rowNode.id,
      SemanticsAction.customAction,
      keepActionId,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Swiggy'), findsNothing);
    await tester.ensureVisible(find.text('Credit shop'));
    await tester.pumpAndSettle();
    final credit = find.bySemanticsLabel(RegExp('Credit shop'));
    final creditLabel = tester.getSemantics(credit).getSemanticsData().label;
    expect(creditLabel, contains('Income'));
    expect(creditLabel, contains(r'$100.00 USD'));
    expect(creditLabel, contains('Low confidence parse'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
    semanticsDisposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await unmountAndCloseDatabase(tester, database);
    databaseClosed = true;
  });

  testWidgets('Review view toggle updates selected mode and destination hint',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    await pumpScreen(tester, [
      reviewItem(
        id: 'mode-review',
        displayName: 'Swiggy',
        counterpartyKey: 'raw:swiggy',
        categoryId: 'Food',
      ),
    ]);

    final card = find.bySemanticsLabel('Card view');
    final cardData = tester.getSemantics(card).getSemanticsData();
    expect(cardData.flagsCollection.isButton, isTrue);
    expect(cardData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(cardData.hint, contains('Switch to list view'));
    final cardRect = tester.getRect(card);
    expect(cardRect.height, greaterThanOrEqualTo(48));
    expect(cardRect.width, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(cardRect.right - 1, cardRect.bottom - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final list = find.bySemanticsLabel('List view');
    final listData = tester.getSemantics(list).getSemanticsData();
    expect(listData.flagsCollection.isButton, isTrue);
    expect(listData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(listData.hint, contains('Switch to card view'));
    expect(card, findsNothing);
    semantics.dispose();
    semanticsDisposed = true;
  });

  testWidgets(
      'Sort action buttons have distinct labels and truthful Back state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    await pumpScreen(tester, [
      reviewItem(
        id: 'first-review',
        displayName: 'Swiggy',
        counterpartyKey: 'raw:swiggy',
        categoryId: 'Food',
      ),
    ]);

    for (final label in [
      'Previous transaction',
      'Change category',
      'Skip to next transaction',
      'Keep',
    ]) {
      final action = find.bySemanticsLabel(label);
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(
        tester.getSemantics(action).rect.height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
      expect(
        tester.getSemantics(action).rect.width,
        greaterThanOrEqualTo(48),
        reason: label,
      );
      expect(tester.getRect(action).width, greaterThanOrEqualTo(48));
    }
    final back = tester
        .getSemantics(find.bySemanticsLabel('Previous transaction'))
        .getSemanticsData();
    expect(back.flagsCollection.isEnabled.toBoolOrNull(), isNotNull);
    expect(back.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
    await tester.tap(find.bySemanticsLabel('Previous transaction'));
    await tester.pump();
    expect(find.text('Swiggy'), findsOneWidget);
    semantics.dispose();
    semanticsDisposed = true;
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
    List<TransactionReviewItem> items, {
    Size size = const Size(402, 874),
    double textScale = 1,
    ReviewViewMode? initialViewMode,
  }) async {
    tester.view.physicalSize = size;
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
          if (initialViewMode != null)
            reviewViewProvider.overrideWith(
              () => _InitialReviewViewNotifier(initialViewMode),
            ),
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
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(textScale),
                ),
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

  testWidgets('Sort QR is available in card and list without resolving row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    final db = await seedDb();
    var databaseClosed = false;
    addTearDown(() async {
      if (!databaseClosed) await unmountAndCloseDatabase(tester, db);
    });
    final container = await pumpSortWithDb(
      tester,
      db,
      [
        reviewItem(
          id: 'txn_001',
          displayName: 'Synthetic Shop',
          counterpartyKey: 'raw:synthetic-shop',
          categoryId: 'food_cat',
          counterpartyVpa: 'synthetic.shop@upi',
        ),
      ],
    );

    for (final listMode in [false, true]) {
      final action = find.byTooltip('Show UPI QR');
      await tester.scrollUntilVisible(action, 100);
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      if (!listMode) {
        final card = find.bySemanticsLabel(
          RegExp(r'^Synthetic Shop, food_cat,'),
        );
        final cardData = tester.getSemantics(card).getSemanticsData();
        expect(cardData.flagsCollection.isButton, isTrue);
        final cardRect = tester.getRect(card);
        expect(cardRect.height, greaterThanOrEqualTo(48));
        expect(cardRect.width, greaterThanOrEqualTo(48));
        await tester.tapAt(Offset(cardRect.right - 1, cardRect.bottom - 1));
        await tester.pumpAndSettle();
        expect(find.text('TRANSACTION DETAILS'), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
      }
      final actionData = tester.getSemantics(action).getSemanticsData();
      expect(actionData.flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(action).rect.height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(action).rect.width, greaterThanOrEqualTo(48));
      final actionRect = tester.getRect(action);
      await tester.tapAt(
        Offset(actionRect.right - 1, actionRect.bottom - 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('UPI QR code'), findsOneWidget);
      expect(find.text('Synthetic Shop'), findsNWidgets(2));
      expect(find.text('synthetic.shop@upi'), findsOneWidget);
      await tester.tap(find.byTooltip('Close QR code'));
      await tester.pumpAndSettle();
      expect(find.text('UPI QR code'), findsNothing);
      expect(find.byTooltip('Show UPI QR'), findsOneWidget);
      expect(find.text('TRANSACTION DETAILS'), findsNothing);

      if (!listMode) {
        await tester.tap(find.byIcon(Icons.view_list_rounded));
        await tester.pumpAndSettle();
      }
    }

    final stored = await (db.select(db.transactions)
          ..where((row) => row.id.equals('txn_001')))
        .getSingle();
    expect(stored.status, 'needs_review');
    expect(container.read(undoControllerProvider), isNull);
    semantics.dispose();
    semanticsDisposed = true;
    await unmountAndCloseDatabase(tester, db);
    databaseClosed = true;
  });

  testWidgets('Sort list QR remains independently accessible at 320dp and 2x',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var semanticsDisposed = false;
    addTearDown(() {
      if (!semanticsDisposed) semantics.dispose();
    });
    final db = await seedDb();
    var databaseClosed = false;
    addTearDown(() async {
      if (!databaseClosed) await unmountAndCloseDatabase(tester, db);
    });
    final container = await pumpSortWithDb(
      tester,
      db,
      [
        reviewItem(
          id: 'txn_001',
          displayName: 'Synthetic Shop',
          counterpartyKey: 'raw:synthetic-shop',
          categoryId: 'food_cat',
          counterpartyVpa: 'synthetic.shop@upi',
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
      initialViewMode: ReviewViewMode.list,
    );

    await tester.scrollUntilVisible(find.byTooltip('Show UPI QR'), 80);
    final action = find.byTooltip('Show UPI QR');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    final actionNode = tester.getSemantics(action);
    final actionData = actionNode.getSemanticsData();
    expect(actionData.flagsCollection.isButton, isTrue);
    expect(actionNode.rect.height, greaterThanOrEqualTo(48));
    expect(actionNode.rect.width, greaterThanOrEqualTo(48));
    final rect = tester.getRect(action);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
    await tester.pumpAndSettle();
    expect(find.text('UPI QR code'), findsOneWidget);
    await tester.tap(find.byTooltip('Close QR code'));
    await tester.pumpAndSettle();

    final stored = await (db.select(db.transactions)
          ..where((row) => row.id.equals('txn_001')))
        .getSingle();
    expect(stored.status, 'needs_review');
    expect(container.read(undoControllerProvider), isNull);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    semanticsDisposed = true;
    await unmountAndCloseDatabase(tester, db);
    databaseClosed = true;
  });

  testWidgets('Sort list row tap opens transaction detail and returns',
      (tester) async {
    final db = await seedDb();
    await pumpSortWithDb(
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
      initialViewMode: ReviewViewMode.list,
    );

    await tester.tap(find.text('Swiggy'));
    await tester.pumpAndSettle();
    expect(find.text('TRANSACTION DETAILS'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.text('TRANSACTION DETAILS'), findsNothing);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountAndCloseDatabase(tester, db);
  });

  testWidgets('card mode back and skip buttons are a matching pair',
      (tester) async {
    await pumpScreen(tester, [
      reviewItem(id: '1', displayName: 'A', counterpartyKey: 'raw:a'),
      reviewItem(id: '2', displayName: 'B', counterpartyKey: 'raw:b'),
    ]);
    final backIcon = find.byIcon(Icons.arrow_back_rounded);
    final nextIcon = find.byIcon(Icons.arrow_forward_rounded);
    expect(backIcon, findsOneWidget);
    expect(nextIcon, findsOneWidget);
    expect(tester.widget<Icon>(backIcon).size, 24);
    expect(tester.widget<Icon>(nextIcon).size, 24);
    Rect circle(Finder icon) => tester.getRect(
          find.ancestor(of: icon, matching: find.byType(Container)).first,
        );
    final back = circle(backIcon);
    final next = circle(nextIcon);
    expect(back.size, next.size);
    expect(back.width, greaterThanOrEqualTo(48));
    expect(back.height, greaterThanOrEqualTo(48));
  });

  group('T-159a — _confirmItem', () {
    testWidgets(
        'Keep persists confirmed status and removes item from visible queue',
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
      final transaction = await (db.select(db.transactions)
            ..where((row) => row.id.equals('txn_001')))
          .getSingle();
      expect(transaction.status, 'confirmed');

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
      final transaction = await (db.select(db.transactions)
            ..where((row) => row.id.equals('txn_001')))
          .getSingle();
      expect(transaction.status, 'needs_review');

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
