import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/manual_entry_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';
import '../../support/fake_activity_transaction_page_controller.dart';

void main() {
  late AppDatabase database;
  // Widget tests close the database themselves (see `unmount` below) so
  // drift's stream-cancellation timer never gets scheduled; this flag stops
  // the shared tearDown from closing it a second time.
  var databaseClosed = false;

  setUp(() async {
    databaseClosed = false;
    database = AppDatabase(NativeDatabase.memory());
    await database.into(database.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: 'food_dining',
            name: 'Food & Dining',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 10,
            isUserCreated: false,
          ),
        );
  });

  tearDown(() async {
    if (!databaseClosed) {
      await database.close();
    }
  });

  // categoryListProvider is fed by a real drift `.watch()` stream, which only
  // delivers under a real event-loop tick. Alternate real-async slices with
  // fake pumps until it resolves. Bounded so a regression fails fast instead
  // of hanging. Must be awaited before `unmount` below: closing the database
  // while that first query is still in flight hangs drift's `close()`
  // forever waiting for it to settle.
  Future<void> drainCategories(WidgetTester tester, Finder scope) async {
    final element = tester.element(scope);
    for (var i = 0; i < 40; i++) {
      final container = ProviderScope.containerOf(element, listen: false);
      if (container.read(categoryListProvider).hasValue) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  // The screens here hold real drift `.watch()` streams (categoryListProvider
  // / transactionListProvider). Cancelling one on ProviderScope dispose
  // schedules a timer inside drift's StreamQueryStore that survives past the
  // end of the test (see the comment on `StreamQueryStore.markAsClosed`),
  // tripping flutter_test's `!timersPending` invariant. Closing the database
  // *before* the widget tree tears down avoids scheduling that timer.
  Future<void> unmount(WidgetTester tester) async {
    databaseClosed = true;
    await database.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<void> pumpEntryScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(home: ManualEntryScreen()),
      ),
    );
    // The category dropdown's `items` snapshot must include the seeded
    // categories by the time a test opens it.
    await drainCategories(tester, find.byType(ManualEntryScreen));
    await tester.pump();
  }

  group('repository', () {
    test(
        'insertManual persists manual/confirmed/cash row that renders in the '
        'list identically to parsed rows', () async {
      final repository = TransactionRepository(database);
      final clockNow = DateTime.utc(2026, 7, 7, 12);

      final id = await repository.insertManual(
        ManualTransactionDraft(
          amount: 320,
          direction: TransactionDirection.debit,
          ts: DateTime.utc(2026, 7, 6, 13, 30),
          categoryId: 'food_dining',
          description: 'Street food lunch',
        ),
        clock: () => clockNow,
      );

      expect(id, startsWith('txn_manual_'));

      final row = await (database.select(database.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.parseSource, 'manual');
      expect(row.status, 'confirmed');
      expect(row.channel, 'cash');
      expect(row.amount, 320);
      expect(row.direction, 'debit');
      expect(row.categoryId, 'food_dining');
      expect(row.description, 'Street food lunch');
      expect(row.smsId, isNull);
      expect(row.isDeleted, isFalse);
      expect(row.duplicateOfTxnId, isNull);
      expect(row.confidenceJson, contains('"c":1.0'));

      // Renders through the same list pipeline as parsed rows: description
      // becomes the display name, category display data is resolved.
      final items = await repository.watchTransactions().first;
      expect(items, hasLength(1));
      expect(items.single.id, id);
      expect(items.single.displayName, 'Street food lunch');
      expect(items.single.categoryName, 'Food & Dining');
      expect(items.single.categoryId, 'food_dining');
      expect(items.single.categoryIcon, 'restaurant');
      expect(items.single.direction, TransactionDirection.debit);
    });
  });

  testWidgets('saving the form persists a manual transaction', (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '250');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Auto rickshaw',
    );

    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & Dining').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = await database.select(database.transactions).get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.amount, 250);
    expect(row.direction, 'debit');
    expect(row.channel, 'cash');
    expect(row.parseSource, 'manual');
    expect(row.status, 'confirmed');
    expect(row.categoryId, 'food_dining');
    expect(row.description, 'Auto rickshaw');

    await unmount(tester);
  });

  testWidgets('credit direction is saved when Received is selected',
      (tester) async {
    await pumpEntryScreen(tester);

    await tester.tap(find.text('Received'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1200',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rows = await database.select(database.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.direction, 'credit');
    expect(rows.single.categoryId, isNull);
    expect(rows.single.description, isNull);

    await unmount(tester);
  });

  testWidgets('invalid amount blocks save with a validation error',
      (tester) async {
    await pumpEntryScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(await database.select(database.transactions).get(), isEmpty);

    await unmount(tester);
  });

  testWidgets('transactions list FAB opens the manual entry form',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          transactionListProvider.overrideWith(
            (ref) => Stream.value(const <TransactionListItem>[]),
          ),
          activityTransactionPageProvider.overrideWith(
            () => FakeActivityTransactionPageController(
              const ActivityTransactionPage(rows: [], hasMore: false),
            ),
          ),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await drainCategories(tester, find.byType(ManualEntryScreen));

    expect(find.byType(ManualEntryScreen), findsOneWidget);
    expect(find.text('Add transaction'), findsOneWidget);

    await unmount(tester);
  });
}
