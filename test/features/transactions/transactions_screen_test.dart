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
  }) {
    return TransactionListItem(
      id: id,
      ts: ts,
      amount: amount,
      direction: direction,
      displayName: displayName,
      categoryName: categoryName,
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
        amount: 500,
        direction: TransactionDirection.credit,
        displayName: 'Salary Inc',
      ),
      item(
        id: 'txn_older',
        ts: now.subtract(const Duration(days: 1)),
        amount: 200,
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
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('+₹500.00'), findsOneWidget);

    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('-₹200.00'), findsOneWidget);

    expect(
      tester.getTopLeft(find.widgetWithText(ListTile, 'Salary Inc')).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Amazon')).dy),
    );
  });

  test('repository resolves names newest-first and excludes soft-deleted rows',
      () async {
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

    final rows =
        await TransactionRepository(database).watchTransactions().first;

    expect(rows.map((row) => row.displayName), ['Salary Inc', 'Amazon']);
    expect(rows.first.direction, TransactionDirection.credit);
    expect(rows.first.categoryName, isNull);
    expect(rows.last.categoryName, 'Shopping');
  });
}
