import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  Future<void> insertReviewTxn(
    AppDatabase database, {
    required String id,
    String? categoryId,
    String? counterpartyKey,
  }) {
    final now = DateTime.utc(2026, 7, 11, 10);
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            categoryId: Value(categoryId),
            merchantRaw: Value(
              counterpartyKey?.startsWith('raw:') == true
                  ? counterpartyKey!.substring(4)
                  : null,
            ),
            counterpartyVpa: Value(
              counterpartyKey?.startsWith('vpa:') == true
                  ? counterpartyKey!.substring(4)
                  : null,
            ),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'needs_review',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

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
      categoryIcon: null,
      status: 'needs_review',
      counterpartyKey: counterpartyKey,
    );
  }

  Future<AppDatabase> pumpActionableScreen(
    WidgetTester tester,
    List<TransactionReviewItem> items, {
    bool autoClose = true,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    if (autoClose) addTearDown(database.close);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'shopping',
            name: 'Shopping',
            icon: 'shopping_bag',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    for (final item in items) {
      await insertReviewTxn(
        database,
        id: item.id,
        categoryId: item.categoryId,
        counterpartyKey: item.counterpartyKey,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
        ],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WeeklyReviewScreen)),
      listen: false,
    );
    await tester.runAsync(
      () => container.read(appDatabaseProvider.future),
    );
    await tester.pumpAndSettle();
    return database;
  }

  Future<void> waitForStatus(
    WidgetTester tester,
    AppDatabase database,
    String txnId,
    String status,
  ) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final current = await tester.runAsync(
        () async => (await (database.select(database.transactions)
                  ..where((t) => t.id.equals(txnId)))
                .getSingle())
            .status,
      );
      if (current == status) return;
    }
    fail('$txnId did not reach $status');
  }

  testWidgets('shows the weekly review empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('All caught up'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt), findsOneWidget);
  });

  testWidgets('opens in guided quick review mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith(
            (ref) => Stream.value([
              TransactionReviewItem(
                id: 'txn_review_1',
                ts: DateTime.utc(2026, 7, 8, 10),
                amount: 1299,
                direction: TransactionDirection.debit,
                displayName: 'Bookstore',
                categoryName: 'Shopping',
                categoryId: 'shopping',
                categoryIcon: 'shopping_bag',
                status: 'needs_review',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Bookstore'), findsOneWidget);
    expect(find.text('Suggested category'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('-₹1,299.00'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets(
      'low-trust review rows explain that transaction details need confirmation',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith(
            (ref) => Stream.value([
              TransactionReviewItem(
                id: 'txn_review_generic',
                ts: DateTime.utc(2026, 7, 8, 10),
                amount: 1299,
                direction: TransactionDirection.debit,
                displayName: 'Bookstore',
                categoryName: 'Shopping',
                categoryId: 'shopping',
                categoryIcon: 'shopping_bag',
                status: 'needs_review',
                isLowTrustParse: true,
              ),
            ]),
          ),
          categoryListProvider.overrideWith(
            (ref) => Stream.value([
              const Category(
                id: 'shopping',
                name: 'Shopping',
                icon: 'shopping_bag',
                isSpending: true,
                sortOrder: 1,
                isUserCreated: false,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: WeeklyReviewScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.text('Some transaction details need confirmation.'),
      findsOneWidget,
    );
    expect(find.text('Change category'), findsOneWidget);
  });

  testWidgets('bulk confirm updates selected statuses only', (tester) async {
    final items = [
      reviewItem(
        id: 'txn_bulk_1',
        displayName: 'Alice',
        counterpartyKey: 'vpa:alice@upi',
      ),
      reviewItem(
        id: 'txn_bulk_2',
        displayName: 'Bookstore',
        counterpartyKey: 'raw:bookstore',
      ),
      reviewItem(
        id: 'txn_bulk_3',
        displayName: 'Cafe',
        counterpartyKey: 'raw:cafe',
      ),
    ];
    final database = await pumpActionableScreen(tester, items);

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('select_txn_bulk_3')));
    await tester.pump();
    await tester.tap(find.text('Confirm selected (2)'));
    await waitForStatus(tester, database, 'txn_bulk_1', 'confirmed');

    final rows = (await tester.runAsync(
      () => database.select(database.transactions).get(),
    ))!;
    expect(
      rows.where((row) => row.status == 'confirmed').map((row) => row.id),
      containsAll(['txn_bulk_1', 'txn_bulk_2']),
    );
    expect(
      rows.singleWhere((row) => row.id == 'txn_bulk_3').status,
      'needs_review',
    );
    expect(rows.every((row) => row.categoryId == null), isTrue);
  });

  testWidgets('category correction requires explicit scope selection',
      (tester) async {
    final item = reviewItem(
      id: 'txn_scope',
      displayName: 'Bookstore',
      counterpartyKey: 'raw:bookstore',
    );
    final database = await pumpActionableScreen(
      tester,
      [item],
      autoClose: false,
    );

    await tester.tap(find.text('Change category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping').last);
    await tester.pumpAndSettle();

    expect(find.text('Apply Shopping to:'), findsOneWidget);
    expect(find.text('This transaction only'), findsOneWidget);
    expect(
      find.text('Future transactions from this merchant'),
      findsOneWidget,
    );
    expect(
      find.text('Existing and future matching transactions'),
      findsOneWidget,
    );

    await tester.tap(find.text('This transaction only'));
    await tester.ensureVisible(find.text('Apply category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply category'));
    await waitForStatus(tester, database, 'txn_scope', 'confirmed');
    await tester.pump();

    final rules = await tester.runAsync(
      () => database.select(database.rules).get(),
    );
    expect(rules, isEmpty);
    expect(find.text('Category updated.'), findsOneWidget);
    expect(find.textContaining('will remember'), findsNothing);
    await tester.runAsync(database.close);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('group confirm updates every row for one counterparty',
      (tester) async {
    final items = [
      reviewItem(
        id: 'txn_group_1',
        displayName: 'Alice',
        counterpartyKey: 'vpa:alice@upi',
      ),
      reviewItem(
        id: 'txn_group_2',
        displayName: 'Alice',
        counterpartyKey: 'vpa:alice@upi',
      ),
      reviewItem(
        id: 'txn_group_other',
        displayName: 'Bob',
        counterpartyKey: 'vpa:bob@upi',
      ),
    ];
    final database = await pumpActionableScreen(tester, items);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 similar transactions from Alice'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm_group_vpa:alice@upi')),
    );
    await waitForStatus(tester, database, 'txn_group_1', 'confirmed');

    final rows = (await tester.runAsync(
      () => database.select(database.transactions).get(),
    ))!;
    expect(
      rows.singleWhere((row) => row.id == 'txn_group_1').status,
      'confirmed',
    );
    expect(
      rows.singleWhere((row) => row.id == 'txn_group_2').status,
      'confirmed',
    );
    expect(
      rows.singleWhere((row) => row.id == 'txn_group_other').status,
      'needs_review',
    );
  });
}
