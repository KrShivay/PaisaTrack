import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/format.dart';
import 'package:paisatrack/core/theme/app_theme.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';
import '../../support/drift_widget_teardown.dart';
import '../../support/fake_activity_transaction_page_controller.dart';
import '../../support/fake_sms_permission_gate.dart';

void main() {
  TransactionListItem item({
    required String id,
    required DateTime ts,
    required double amount,
    required TransactionDirection direction,
    required String displayName,
    String? categoryName,
    String? categoryId,
    String? categoryIcon,
    String? merchantId,
    String? merchantRaw,
    String? accountHint,
    String channel = 'unknown',
    String? note,
    String? reference,
    String? currencyCode = 'INR',
    String? currencySymbol = '₹',
    String status = 'confirmed',
    String parseSource = 'unknown',
  }) {
    return TransactionListItem(
      id: id,
      ts: ts,
      amount: amount,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      direction: direction,
      displayName: displayName,
      categoryName: categoryName,
      categoryId: categoryId,
      categoryIcon: categoryIcon ?? 'food',
      merchantId: merchantId,
      merchantRaw: merchantRaw,
      accountHint: accountHint,
      channel: channel,
      note: note,
      reference: reference,
      status: status,
      parseSource: parseSource,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<TransactionListItem> transactions, {
    bool hasMore = false,
    ActivityTransactionPage? nextPage,
    Size size = const Size(402, 874),
    double textScale = 1,
    double leftInset = 0,
    double rightInset = 0,
    AppDatabase? database,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding(left: leftInset, right: rightInset);
    tester.view.viewPadding =
        FakeViewPadding(left: leftInset, right: rightInset);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (database != null)
            appDatabaseProvider.overrideWith((ref) async => database),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          activityTransactionPageProvider.overrideWith(
            () => FakeActivityTransactionPageController(
              ActivityTransactionPage(rows: transactions, hasMore: hasMore),
              nextPage: nextPage,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows an empty state with no transactions', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No transactions found'), findsOneWidget);
  });

  testWidgets('filter chips expose selection and 48dp edge targets at 2x',
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
      const [],
      size: const Size(320, 568),
      textScale: 2,
      database: database,
    );
    await tester.scrollUntilVisible(
      find.text('All'),
      100,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    final all = find.bySemanticsLabel('All');
    await tester.ensureVisible(all);
    await tester.pumpAndSettle();
    final allNode = tester.getSemantics(all);
    final allData = allNode.getSemanticsData();
    expect(allData.flagsCollection.isButton, isTrue);
    expect(allData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    final allSemanticRect = MatrixUtils.transformRect(
      allNode.transform ?? Matrix4.identity(),
      allNode.rect,
    );
    expect(allSemanticRect.height, greaterThanOrEqualTo(48));
    expect(allSemanticRect.width, greaterThanOrEqualTo(48));
    expect(tester.getRect(all).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(all).width, greaterThanOrEqualTo(48));

    final horizontalScroll = tester
        .state<ScrollableState>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.right,
              )
              .first,
        )
        .position;
    horizontalScroll.jumpTo(horizontalScroll.maxScrollExtent);
    await tester.pump();
    final expenses = find.bySemanticsLabel('Expenses');
    await tester.ensureVisible(expenses);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(expenses)
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isFalse,
    );
    final expensesNode = tester.getSemantics(expenses);
    final semanticRect = MatrixUtils.transformRect(
      expensesNode.transform ?? Matrix4.identity(),
      expensesNode.rect,
    );
    final rect = tester.getRect(expenses);
    expect(semanticRect.height, greaterThanOrEqualTo(48));
    expect(semanticRect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
    await tester.pump();
    expect(
      tester
          .getSemantics(expenses)
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );
    expect(
      tester
          .getSemantics(all)
          .getSemanticsData()
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isFalse,
    );

    final searchField = find.byType(TextField);
    await tester.ensureVisible(searchField);
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'search target');
    await tester.pumpAndSettle();
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(
      editable.size.height,
      greaterThanOrEqualTo(editable.preferredLineHeight),
    );
    final clear = find.byTooltip('Clear search');
    final clearRect = tester.getRect(clear);
    final clearNode = tester.getSemantics(clear);
    final clearSemanticRect = MatrixUtils.transformRect(
      clearNode.transform ?? Matrix4.identity(),
      clearNode.rect,
    );
    expect(clearSemanticRect.height, greaterThanOrEqualTo(48));
    expect(clearSemanticRect.width, greaterThanOrEqualTo(48));
    expect(clearRect.height, greaterThanOrEqualTo(48));
    expect(clearRect.width, greaterThanOrEqualTo(48));
    await tester.tapAt(Offset(clearRect.right - 1, clearRect.bottom - 1));
    await tester.pump();
    expect(find.text('Search transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    semanticsDisposed = true;
    await unmountAndCloseDatabase(tester, database);
    databaseClosed = true;
  });

  testWidgets('Activity transaction rows expose payee and amount as buttons',
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
        item(
          id: 'accessible-activity-row',
          ts: DateTime.utc(2026, 7, 6, 9),
          amount: 100,
          direction: TransactionDirection.debit,
          displayName: 'Amazon accessibility row',
          status: 'needs_review',
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
      database: database,
    );

    final row = find.bySemanticsLabel(RegExp('Amazon accessibility row'));
    final data = tester.getSemantics(row).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.label, contains('Amazon accessibility row'));
    expect(data.label, contains('₹100'));
    expect(
      data.label,
      contains(formatActivityDateGroup(DateTime.utc(2026, 7, 6, 9))),
    );
    expect(data.label, contains('Status needs review'));
    expect(tester.getSemantics(row).rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(row).rect.width, greaterThanOrEqualTo(48));
    expect(tester.getRect(row).height, greaterThanOrEqualTo(48));
    expect(tester.getRect(row).width, greaterThanOrEqualTo(48));
    final rect = tester.getRect(row);
    await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    semantics.dispose();
    semanticsDisposed = true;
    await unmountAndCloseDatabase(tester, database);
    databaseClosed = true;
  });

  testWidgets('Activity row uses the shared localized transaction clock',
      (tester) async {
    final instant = DateTime.utc(2026, 7, 10, 18, 30);
    final storedEpoch = instant.millisecondsSinceEpoch;
    await pumpScreen(
      tester,
      [
        item(
          id: 'utc-activity-row',
          ts: instant,
          amount: 42,
          direction: TransactionDirection.debit,
          displayName: 'UTC activity row',
        ),
      ],
    );

    expect(find.textContaining(formatTxnClockTime(instant)), findsOneWidget);
    if (DateTime.now().timeZoneOffset ==
        const Duration(hours: 5, minutes: 30)) {
      expect(find.textContaining('12:00 am'), findsOneWidget);
    }
    expect(instant.millisecondsSinceEpoch, storedEpoch);
  });

  testWidgets('keeps long foreign-currency amounts readable at 2× text',
      (tester) async {
    await pumpScreen(
      tester,
      [
        item(
          id: 'long-usd-amount',
          ts: DateTime(2026, 9, 29, 10),
          amount: 1234567890123.45,
          direction: TransactionDirection.debit,
          displayName: 'International merchant',
          currencyCode: 'USD',
          currencySymbol: r'$',
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
    );

    final amount = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data?.contains('1234567890123.45') == true &&
          widget.maxLines == 2,
    );
    expect(amount, findsOneWidget);
    expect(tester.widget<Text>(amount).maxLines, 2);
    expect(tester.getSize(amount).height, greaterThan(36));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity header has no overflow at 320×568 and 2× text',
      (tester) async {
    await pumpScreen(
      tester,
      [_screenItem('responsive')],
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity header has no overflow on a 360dp-wide phone',
      (tester) async {
    await pumpScreen(
      tester,
      [_screenItem('responsive')],
      size: const Size(360, 640),
    );

    expect(find.text('Add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'short landscape Activity scrolls its heading away and keeps search reachable',
      (tester) async {
    await pumpScreen(
      tester,
      [for (var index = 0; index < 16; index++) _screenItem('compact-$index')],
      size: const Size(964, 434),
      textScale: 2,
      leftInset: 40,
      rightInset: 40,
    );

    final title = find.text('Activity');
    expect(title, findsOneWidget);
    final activityScroll = find.byType(CustomScrollView);
    expect(activityScroll, findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: activityScroll,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          ),
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(title, findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.getRect(find.byType(TextField)).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(find.byType(TextField)).bottom, lessThan(434));
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait Activity keeps its standard header layout at 1× text',
      (tester) async {
    await pumpScreen(tester, [_screenItem('portrait')]);

    final titleRect = tester.getRect(find.text('Activity'));
    final statusRect = tester.getRect(find.text('SMS access is on'));
    final searchRect = tester.getRect(find.byType(TextField));
    final firstRowRect = tester.getRect(find.text('Portrait payment'));

    expect(titleRect.top, closeTo(24.5, 1));
    expect(titleRect.bottom, lessThan(statusRect.top));
    expect(statusRect.bottom, lessThan(searchRect.top));
    expect(searchRect.bottom, lessThan(firstRowRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows initial load error and retries into loaded transactions',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = _ControlledTransactionRepository(database);
    addTearDown(() async {
      await repository.close();
      await database.close();
    });
    await _pumpWithRepository(tester, database, repository);
    await tester.pump();
    repository.controllers.single.addError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No transactions found'), findsNothing);
    expect(find.text('Couldn’t load transactions. Try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await _pumpUntilControllerCount(tester, repository, 2);
    final recovered = _screenItem('recovered');
    repository.controllers.last.add(
      ActivityTransactionPage(rows: [recovered], hasMore: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recovered payment'), findsOneWidget);
    expect(find.text('No transactions found'), findsNothing);
  });

  testWidgets('keeps loaded transactions visible after a later query error',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = _ControlledTransactionRepository(database);
    addTearDown(() async {
      await repository.close();
      await database.close();
    });
    final container = await _pumpWithRepository(tester, database, repository);
    await tester.pump();
    repository.controllers.single.add(
      ActivityTransactionPage(
        rows: [_screenItem('original')],
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    repository.controllers.single.addError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(activityTransactionPageProvider).hasError, isTrue);
    expect(container.read(activityTransactionPageProvider).hasValue, isTrue);
    expect(find.text('Original payment'), findsOneWidget);
    expect(find.text('Couldn’t refresh transactions.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _pumpUntilControllerCount(tester, repository, 2);
    repository.controllers.last.add(
      ActivityTransactionPage(
        rows: [_screenItem('after-retry')],
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('After-retry payment'), findsOneWidget);
    expect(find.text('Couldn’t refresh transactions.'), findsNothing);
  });

  testWidgets('shows page-two load error and retries from a fresh snapshot',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = _ControlledTransactionRepository(database);
    final container = await _pumpWithRepository(tester, database, repository);
    addTearDown(() async {
      await repository.close();
      await database.close();
    });
    await tester.pump();
    const cursor = ActivityTransactionCursor(ts: 1, id: 'first-page');
    repository.controllers.single.add(
      ActivityTransactionPage(
        rows: [_screenItem('page-one')],
        hasMore: true,
        nextCursor: cursor,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Load more transactions'));
    await _pumpUntilControllerCount(tester, repository, 2);
    expect(repository.cursors, [null, cursor]);
    repository.controllers[1].addError(StateError('page two unavailable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(activityTransactionPageProvider).hasError, isTrue);
    expect(container.read(activityTransactionPageProvider).hasValue, isTrue);
    expect(find.text('Page-one payment'), findsOneWidget);
    expect(find.text('Couldn’t refresh transactions.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await _pumpUntilControllerCount(tester, repository, 3);
    expect(repository.cursors.last, isNull);
    repository.controllers.last.add(
      ActivityTransactionPage(
        rows: [_screenItem('fresh-snapshot')],
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Fresh-snapshot payment'), findsOneWidget);
    expect(find.text('Couldn’t refresh transactions.'), findsNothing);
  });

  testWidgets('renders parsed transactions newest-first with display names',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      item(
        id: 'txn_newest',
        ts: now,
        amount: 1234567.89,
        direction: TransactionDirection.credit,
        displayName: 'Salary Inc',
      ),
      item(
        id: 'txn_older',
        ts: now.subtract(const Duration(days: 1)),
        amount: 200000,
        direction: TransactionDirection.debit,
        displayName: 'Amazon',
        categoryName: 'Shopping',
      ),
    ]);

    expect(find.text('Salary Inc'), findsOneWidget);
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.byType(BloomAmount), findsWidgets);
  });

  testWidgets('keeps matching month and day separate across years',
      (tester) async {
    final now = DateTime.now();
    final nowDate = DateTime.utc(now.year, now.month, now.day);
    final currentDate = [
      DateTime(now.year, 1, 15, 12),
      DateTime(now.year, 7, 15, 12),
    ].firstWhere((candidate) {
      final candidateDate =
          DateTime.utc(candidate.year, candidate.month, candidate.day);
      return nowDate.difference(candidateDate).inDays.abs() > 2;
    });
    final priorYearDate = DateTime(
      currentDate.year - 1,
      currentDate.month,
      currentDate.day,
      12,
    );
    final transactions = [
      item(
        id: 'current-inr',
        ts: currentDate,
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Current year INR',
      ),
      item(
        id: 'current-usd',
        ts: currentDate,
        amount: 10,
        direction: TransactionDirection.debit,
        displayName: 'Current year USD',
        currencyCode: 'USD',
        currencySymbol: r'$',
      ),
      item(
        id: 'prior-inr',
        ts: priorYearDate,
        amount: 200,
        direction: TransactionDirection.debit,
        displayName: 'Prior year INR',
      ),
      item(
        id: 'prior-usd',
        ts: priorYearDate,
        amount: 20,
        direction: TransactionDirection.debit,
        displayName: 'Prior year USD',
        currencyCode: 'USD',
        currencySymbol: r'$',
      ),
    ];
    final epochs = transactions.map((transaction) => transaction.ts).toList();

    await pumpScreen(tester, transactions);

    final month = const [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ][currentDate.month - 1];
    expect(find.text('$month ${currentDate.day}'), findsOneWidget);
    expect(
      find.text('$month ${priorYearDate.day} ${priorYearDate.year}'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('$month ${currentDate.day}')).dy,
      lessThan(
        tester
            .getTopLeft(
              find.text('$month ${priorYearDate.day} ${priorYearDate.year}'),
            )
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('Current year INR')).dy,
      lessThan(tester.getTopLeft(find.text('Prior year INR')).dy),
    );
    expect(find.text(r'-₹100.00 · -$10.00 USD'), findsOneWidget);
    expect(find.text(r'-₹200.00 · -$20.00 USD'), findsOneWidget);
    expect(
      transactions.map((transaction) => transaction.ts).toList(),
      epochs,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('groups transaction instants by local date at midnight',
      (tester) async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final beforeMidnight = midnight.subtract(const Duration(milliseconds: 1));
    final afterMidnight = midnight.add(const Duration(milliseconds: 1));
    final epochs = [
      beforeMidnight.millisecondsSinceEpoch,
      afterMidnight.millisecondsSinceEpoch,
    ];

    await pumpScreen(tester, [
      item(
        id: 'after-midnight',
        ts: afterMidnight.toUtc(),
        amount: 1,
        direction: TransactionDirection.debit,
        displayName: 'After midnight',
      ),
      item(
        id: 'before-midnight',
        ts: beforeMidnight.toUtc(),
        amount: 2,
        direction: TransactionDirection.debit,
        displayName: 'Before midnight',
      ),
    ]);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(afterMidnight.millisecondsSinceEpoch, epochs[1]);
    expect(beforeMidnight.millisecondsSinceEpoch, epochs[0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps SMS import available after transactions exist',
      (tester) async {
    await pumpScreen(tester, [
      item(
        id: 'existing',
        ts: DateTime.utc(2026, 7, 6, 9),
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Existing payment',
      ),
    ]);

    expect(find.byTooltip('Scan SMS inbox'), findsOneWidget);
  });

  testWidgets('hides the continuation action when the page is terminal',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    final transaction = item(
      id: 'page-row',
      ts: now,
      amount: 100,
      direction: TransactionDirection.debit,
      displayName: 'Page row',
    );

    await pumpScreen(tester, [transaction]);
    expect(find.text('Load more transactions'), findsNothing);
  });

  testWidgets('shows the continuation action when the page has more',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    final transaction = item(
      id: 'page-row',
      ts: now,
      amount: 100,
      direction: TransactionDirection.debit,
      displayName: 'Page row',
    );

    await pumpScreen(tester, [transaction], hasMore: true);
    expect(find.text('Load more transactions'), findsOneWidget);
  });

  testWidgets('keeps the continuation action at least 48dp in landscape',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(
      tester,
      [
        item(
          id: 'page-row',
          ts: now,
          amount: 100,
          direction: TransactionDirection.debit,
          displayName: 'Page row',
        ),
      ],
      hasMore: true,
      size: const Size(602, 271),
    );
    // Short viewports scroll the header with the list, so the trailing
    // action is built lazily; bring it on screen before measuring.
    await tester.scrollUntilVisible(
      find.text('Load more transactions'),
      100,
      scrollable: find.byType(Scrollable).first,
    );

    final button = find.ancestor(
      of: find.text('Load more transactions'),
      matching: find.byType(OutlinedButton),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final semanticHeight = tester.getSemantics(button).rect.height;
    semantics.dispose();
    expect(semanticHeight, greaterThanOrEqualTo(48));
  });

  testWidgets('search filters the list by merchant name', (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      item(
        id: 'a',
        ts: now,
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Amazon',
      ),
      item(
        id: 'b',
        ts: now,
        amount: 200,
        direction: TransactionDirection.credit,
        displayName: 'Salary Inc',
      ),
    ]);

    await tester.enterText(find.byType(TextField), 'amazon');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Amazon'), findsWidgets);
    expect(find.text('Salary Inc'), findsNothing);
  });

  testWidgets(
      'keeps paging available when the search match is on an older page',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    final olderMatch = item(
      id: 'older_salary',
      ts: now.subtract(const Duration(days: 2)),
      amount: 50000,
      direction: TransactionDirection.credit,
      displayName: 'Salary Inc',
    );
    await pumpScreen(
      tester,
      [
        item(
          id: 'current',
          ts: now,
          amount: 100,
          direction: TransactionDirection.debit,
          displayName: 'Coffee Shop',
        ),
      ],
      hasMore: true,
      nextPage: ActivityTransactionPage(
        rows: [olderMatch],
        hasMore: false,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Salary');
    await tester.pump();

    expect(find.text('No transactions matching "Salary"'), findsOneWidget);
    expect(find.text('Load more transactions'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Salary',
    );

    await tester.tap(find.text('Load more transactions'));
    await tester.pump();

    expect(find.text('Salary Inc'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Salary',
    );
  });
}

Future<ProviderContainer> _pumpWithRepository(
  WidgetTester tester,
  AppDatabase database,
  _ControlledTransactionRepository repository,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => database),
      transactionRepositoryProvider.overrideWith((ref, db) => repository),
      smsPermissionGateProvider.overrideWithValue(
        FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TransactionsScreen()),
    ),
  );
  return container;
}

Future<void> _pumpUntilControllerCount(
  WidgetTester tester,
  _ControlledTransactionRepository repository,
  int count,
) async {
  for (var attempt = 0;
      attempt < 6 && repository.controllers.length < count;
      attempt++) {
    await tester.pump();
  }
  expect(repository.controllers, hasLength(count));
}

TransactionListItem _screenItem(String id) => TransactionListItem(
      id: id,
      ts: DateTime.utc(2026, 7, 6, 9),
      amount: 100,
      currencyCode: 'INR',
      currencySymbol: '₹',
      direction: TransactionDirection.debit,
      displayName: '${id[0].toUpperCase()}${id.substring(1)} payment',
      categoryName: null,
      categoryId: null,
      categoryIcon: 'food',
      channel: 'unknown',
      status: 'confirmed',
      parseSource: 'unknown',
    );

class _ControlledTransactionRepository extends TransactionRepository {
  _ControlledTransactionRepository(super.database);

  final controllers = <StreamController<ActivityTransactionPage>>[];
  final cursors = <ActivityTransactionCursor?>[];

  @override
  Stream<ActivityTransactionPage> watchTransactionPage({
    int limit = 100,
    DateTime? start,
    DateTime? end,
    ActivityTransactionCursor? cursor,
    Set<String>? transactionIds,
  }) {
    assert(transactionIds == null || transactionIds.isNotEmpty);
    final controller = StreamController<ActivityTransactionPage>();
    cursors.add(cursor);
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers) {
      await controller.close();
    }
  }
}
