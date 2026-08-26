import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';
import '../../support/fake_activity_transaction_page_controller.dart';

TransactionListItem testItem({
  required String id,
  required String name,
  required double amount,
  required TransactionDirection direction,
  DateTime? ts,
}) {
  return TransactionListItem(
    id: id,
    ts: ts ?? DateTime.now(),
    amount: amount,
    direction: direction,
    displayName: name,
    categoryName: 'Food',
    categoryId: 'food_dining',
    categoryIcon: 'food',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpActivity(
    WidgetTester tester,
    List<TransactionListItem> items,
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
          activityTransactionPageProvider.overrideWith(
            () => FakeActivityTransactionPageController(
              ActivityTransactionPage(rows: items, hasMore: false),
            ),
          ),
        ],
        child: const MaterialApp(
          home: BloomUndoToastHost(
            child: TransactionsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom Activity / TransactionsScreen', () {
    testWidgets('renders Activity title, search bar, and filter chips',
        (tester) async {
      await pumpActivity(tester, const []);

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Search merchant, note, amount...'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
    });

    testWidgets('renders day-grouped transaction rows with Bloom components',
        (tester) async {
      final items = [
        testItem(
          id: '1',
          name: 'Swiggy',
          amount: 340.0,
          direction: TransactionDirection.debit,
        ),
        testItem(
          id: '2',
          name: 'Salary',
          amount: 50000.0,
          direction: TransactionDirection.credit,
        ),
      ];

      await pumpActivity(tester, items);

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.byType(BloomCategoryTile), findsWidgets);
      expect(find.byType(BloomAmount), findsWidgets);
    });

    testWidgets('filtering by Expenses hides income transactions',
        (tester) async {
      final items = [
        testItem(
          id: '1',
          name: 'Swiggy',
          amount: 340.0,
          direction: TransactionDirection.debit,
        ),
        testItem(
          id: '2',
          name: 'Salary',
          amount: 50000.0,
          direction: TransactionDirection.credit,
        ),
      ];

      await pumpActivity(tester, items);

      await tester.tap(find.text('Expenses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
    });

    testWidgets('search filters list in real-time', (tester) async {
      final items = [
        testItem(
          id: '1',
          name: 'Swiggy',
          amount: 340.0,
          direction: TransactionDirection.debit,
        ),
        testItem(
          id: '2',
          name: 'Blinkit',
          amount: 220.0,
          direction: TransactionDirection.debit,
        ),
      ];

      await pumpActivity(tester, items);

      await tester.enterText(
        find.byType(TextField),
        'Blinkit',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // debounce delay

      expect(find.text('Blinkit'), findsWidgets);
      expect(find.text('Swiggy'), findsNothing);
    });
  });
}
