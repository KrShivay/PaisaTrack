import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';
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
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows an empty state with no transactions', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No transactions found'), findsOneWidget);
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

  @override
  Stream<ActivityTransactionPage> watchTransactionPage({
    int limit = 100,
    DateTime? start,
    DateTime? end,
    ActivityTransactionCursor? cursor,
  }) {
    final controller = StreamController<ActivityTransactionPage>();
    controllers.add(controller);
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers) {
      await controller.close();
    }
  }
}
