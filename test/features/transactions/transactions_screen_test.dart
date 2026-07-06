import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state with no transactions', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No transactions yet'), findsOneWidget);

    // flutter_test disposes the widget tree (and drift's watch() stream)
    // before any tearDown/addTearDown callback runs, so close() must happen
    // here, before the test body returns, or drift's markAsClosed() schedules
    // a debounce Timer.run that outlives the test — see the comment in
    // drift's StreamQueryStore.markAsClosed.
    await database.close();
  });

  testWidgets(
      'renders parsed transactions newest-first with merchant/category names',
      (tester) async {
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

    await pumpScreen(tester);

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

    // Newest transaction renders first.
    expect(
      tester.getTopLeft((find.widgetWithText(ListTile, 'Salary Inc'))).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Amazon')).dy),
    );

    await database.close();
  });

  testWidgets('excludes soft-deleted (duplicate-suppressed) transactions',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);

    await database.into(database.transactions).insertOnConflictUpdate(
          TransactionsCompanion.insert(
            id: 'txn_deleted',
            ts: now.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('Hidden Merchant'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            isDeleted: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await pumpScreen(tester);

    expect(find.text('Hidden Merchant'), findsNothing);
    expect(find.text('No transactions yet'), findsOneWidget);

    await database.close();
  });
}
