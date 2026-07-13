import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

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
    String status = 'confirmed',
    String parseSource = 'unknown',
  }) {
    return TransactionListItem(
      id: id,
      ts: ts,
      amount: amount,
      direction: direction,
      displayName: displayName,
      categoryName: categoryName,
      categoryId: categoryId,
      categoryIcon: categoryIcon,
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
    List<TransactionListItem> transactions,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionListProvider.overrideWith(
            (ref) => Stream.value(transactions),
          ),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows an empty state with no transactions', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No transactions yet'), findsOneWidget);
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

    final tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList(growable: false);
    expect(tiles, hasLength(2));

    expect(find.text('Salary Inc'), findsOneWidget);
    // Subtitle is now "category · time"; match the category prefix only.
    expect(find.textContaining('Uncategorized'), findsOneWidget);
    expect(find.text('+₹12,34,567.89'), findsOneWidget);

    expect(find.text('Amazon'), findsOneWidget);
    expect(find.textContaining('Shopping'), findsOneWidget);
    expect(find.text('-₹2,00,000.00'), findsOneWidget);

    expect(
      tester.getTopLeft(find.widgetWithText(ListTile, 'Salary Inc')).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Amazon')).dy),
    );
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

    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Salary Inc'), findsNothing);
  });

  testWidgets('search covers account, channel, note, reference and status',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      item(
        id: 'a',
        ts: now,
        amount: 610,
        direction: TransactionDirection.debit,
        displayName: 'Zomato',
        accountHint: 'xx6265',
        channel: 'upi',
        note: 'Team lunch',
        reference: 'UTR123456',
        status: 'needs_review',
      ),
      item(
        id: 'b',
        ts: now,
        amount: 200,
        direction: TransactionDirection.debit,
        displayName: 'Amazon',
      ),
    ]);

    expect(
      find.widgetWithText(TextField, 'Search transactions'),
      findsOneWidget,
    );
    for (final query in [
      'xx6265',
      'upi',
      'team lunch',
      'utr123456',
      'needs review',
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.text('Amazon'), findsNothing);
    }
  });

  testWidgets('filter sheet applies amount filter and exposes removable chip',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      item(
        id: 'small',
        ts: now,
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Corner shop',
        categoryId: 'groceries',
        categoryName: 'Groceries',
        accountHint: 'xx6265',
        channel: 'upi',
      ),
      item(
        id: 'large',
        ts: now,
        amount: 500,
        direction: TransactionDirection.debit,
        displayName: 'Supermarket',
        categoryId: 'groceries',
        categoryName: 'Groceries',
        accountHint: 'xx6265',
        channel: 'card',
      ),
    ]);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Filter transactions'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Merchant'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Channel'), findsOneWidget);
    expect(find.text('Review status'), findsOneWidget);
    expect(find.text('Recurring state'), findsOneWidget);
    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Anomaly status'), findsOneWidget);

    final minimumField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Minimum amount',
    );
    await tester.enterText(minimumField, '200');
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.text('Corner shop'), findsNothing);
    expect(find.text('Supermarket'), findsOneWidget);
    final chipFinder = find.widgetWithText(InputChip, 'At least ₹200');
    expect(chipFinder, findsOneWidget);

    tester.widget<InputChip>(chipFinder).onDeleted!();
    await tester.pump();
    expect(find.text('Corner shop'), findsOneWidget);
  });

  testWidgets('search remains active after returning from transaction detail',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      item(
        id: 'amazon',
        ts: now,
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Amazon',
      ),
      item(
        id: 'salary',
        ts: now,
        amount: 1000,
        direction: TransactionDirection.credit,
        displayName: 'Salary Inc',
      ),
    ]);

    await tester.enterText(find.byType(TextField), 'amazon');
    await tester.tap(find.text('Amazon'));
    await tester.pump();
    Navigator.of(tester.element(find.byType(TransactionsScreen))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Salary Inc'), findsNothing);
    expect(find.text('amazon'), findsOneWidget);
  });

  testWidgets('long-press enters multi-select and toggles selection',
      (tester) async {
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

    await tester.longPress(find.text('Amazon'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    // A second tap while in selection mode adds to the selection.
    await tester.tap(find.text('Salary Inc'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // Clearing exits selection mode.
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    expect(find.text('2 selected'), findsNothing);
    expect(find.text('Transactions'), findsOneWidget);
  });

  testWidgets('non-spending debit renders in a neutral color, not debit red',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      TransactionListItem(
        id: 'transfer',
        ts: now,
        amount: 500,
        direction: TransactionDirection.debit,
        displayName: 'Self transfer',
        categoryName: 'Transfers',
        categoryId: 'transfers',
        categoryIcon: 'swap_horiz',
        categoryIsSpending: false,
      ),
    ]);

    final amount = tester.widget<Text>(find.text('-₹500.00'));
    final color = amount.style?.color;
    // Neutral onSurface, never the debit rose hue.
    expect(color, isNot(const Color(0xFFF48A8A))); // debitDark
    expect(color, isNot(const Color(0xFFD64545))); // debitLight
  });

  test(
      'repository resolves names newest-first and excludes soft-deleted and '
      'duplicate-suppressed rows', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 6, 9);

    await database.into(database.merchants).insertOnConflictUpdate(
          MerchantsCompanion.insert(
            id: 'merch_1',
            canonicalName: 'Amazon',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: 'cat_shopping',
            name: 'Shopping',
            icon: 'shopping_bag',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );

    Future<void> insertTxn({
      required String id,
      required DateTime ts,
      required double amount,
      required String direction,
      String? merchantId,
      String? merchantRaw,
      String? categoryId,
      bool isDeleted = false,
      String? duplicateOfTxnId,
    }) {
      return database.into(database.transactions).insertOnConflictUpdate(
            TransactionsCompanion.insert(
              id: id,
              ts: ts.millisecondsSinceEpoch,
              amount: amount,
              direction: direction,
              channel: 'upi',
              merchantId: Value(merchantId),
              merchantRaw: Value(merchantRaw),
              categoryId: Value(categoryId),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'auto',
              isDeleted: Value(isDeleted),
              duplicateOfTxnId: Value(duplicateOfTxnId),
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }

    await insertTxn(
      id: 'txn_older',
      ts: now.subtract(const Duration(days: 1)),
      amount: 200,
      direction: 'debit',
      merchantId: 'merch_1',
      categoryId: 'cat_shopping',
    );
    await insertTxn(
      id: 'txn_newest',
      ts: now,
      amount: 500,
      direction: 'credit',
      merchantRaw: 'Salary Inc',
    );
    await insertTxn(
      id: 'txn_deleted',
      ts: now.add(const Duration(minutes: 1)),
      amount: 100,
      direction: 'debit',
      merchantRaw: 'Hidden Merchant',
      isDeleted: true,
    );
    await insertTxn(
      id: 'txn_dup_echo',
      ts: now.add(const Duration(minutes: 2)),
      amount: 300,
      direction: 'debit',
      merchantRaw: 'Echo Merchant',
      duplicateOfTxnId: 'txn_older',
    );

    final rows =
        await TransactionRepository(database).watchTransactions().first;

    expect(rows.map((row) => row.displayName), ['Salary Inc', 'Amazon']);
    expect(rows.first.direction, TransactionDirection.credit);
    expect(rows.first.categoryName, isNull);
    expect(rows.last.categoryName, 'Shopping');
    expect(rows.last.categoryId, 'cat_shopping');
    expect(rows.last.categoryIcon, 'shopping_bag');
  });
}
