import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

TransactionReviewItem testReviewItem({
  required String id,
  required String name,
  required double amount,
  required TransactionDirection direction,
}) {
  return TransactionReviewItem(
    id: id,
    ts: DateTime.now(),
    amount: amount,
    direction: direction,
    displayName: name,
    categoryName: 'Food',
    categoryId: 'food_dining',
    categoryIcon: 'food',
    status: 'needs_review',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSort(
    WidgetTester tester,
    List<TransactionReviewItem> items,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
        ],
        child: const MaterialApp(
          home: BloomUndoToastHost(
            child: WeeklyReviewScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom Sort / WeeklyReviewScreen', () {
    testWidgets('renders Inbox Zero view when queue is empty', (tester) async {
      await pumpSort(tester, const []);

      expect(find.text('Inbox Zero!'), findsOneWidget);
      expect(
        find.text('You sorted all transactions for today.'),
        findsOneWidget,
      );
      expect(find.byType(BloomMascot), findsOneWidget);
    });

    testWidgets(
        'renders Tinder-style sort card with category tile and hero amount',
        (tester) async {
      final items = [
        testReviewItem(
          id: '1',
          name: 'Zomato',
          amount: 450.0,
          direction: TransactionDirection.debit,
        ),
      ];

      await pumpSort(tester, items);

      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.byType(BloomCategoryTile), findsOneWidget);
      expect(find.byType(BloomAmount), findsOneWidget);
    });

    testWidgets('tapping Keep action advances to Inbox Zero when last item',
        (tester) async {
      final items = [
        testReviewItem(
          id: '1',
          name: 'Zomato',
          amount: 450.0,
          direction: TransactionDirection.debit,
        ),
      ];

      await pumpSort(tester, items);

      expect(find.text('Zomato'), findsOneWidget);

      final keepButton = find.byIcon(Icons.check_rounded);
      await tester.tap(keepButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Inbox Zero!'), findsOneWidget);
    });
  });
}
