import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class FakeUndoController extends UndoController {
  @override
  void pushUndo(UndoToken token) {
    state = token;
  }
}

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith((ref) => Stream.value(items)),
          categoryListProvider.overrideWith(
            (ref) => Stream.value([
              const Category(
                id: 'food_dining',
                name: 'Food & Dining',
                icon: 'restaurant',
                isSpending: true,
                sortOrder: 10,
                isUserCreated: false,
              ),
            ]),
          ),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
          undoControllerProvider.overrideWith(() => FakeUndoController()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
  }

  group('Sort persistence safety (T-123)', () {
    testWidgets('Skipping item cycles to next item without false Inbox Zero',
        (tester) async {
      final items = [
        testReviewItem(
          id: '1',
          name: 'Zomato',
          amount: 450.0,
          direction: TransactionDirection.debit,
        ),
        testReviewItem(
          id: '2',
          name: 'Swiggy',
          amount: 300.0,
          direction: TransactionDirection.debit,
        ),
      ];

      await pumpSort(tester, items);

      expect(find.text('Zomato'), findsOneWidget);

      final skipButton = find.byIcon(Icons.skip_next_rounded);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // Swiggy should now be visible
      expect(find.text('Swiggy'), findsOneWidget);

      // Skip Swiggy as well
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // Should show Inbox Zero or cycle back depending on design, but not break index out of bounds
      expect(find.byType(WeeklyReviewScreen), findsOneWidget);
    });
  });

  group('T-153a — cursor-based queue', () {
    testWidgets(
        'skip advances cursor without removing item — counter shows non-zero position',
        (tester) async {
      final items = [
        testReviewItem(
          id: '1',
          name: 'Zomato',
          amount: 450.0,
          direction: TransactionDirection.debit,
        ),
        testReviewItem(
          id: '2',
          name: 'Swiggy',
          amount: 300.0,
          direction: TransactionDirection.debit,
        ),
        testReviewItem(
          id: '3',
          name: 'Blinkit',
          amount: 200.0,
          direction: TransactionDirection.debit,
        ),
      ];

      await pumpSort(tester, items);

      // Cursor at 0: counter shows "1 of 3"
      expect(find.text('1 of 3'), findsOneWidget);

      final skipButton = find.byIcon(Icons.skip_next_rounded);

      // Skip item 1 — cursor advances to 1
      await tester.tap(skipButton);
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);
      // Counter at non-zero cursor: "2 of 3" — skipped item still in queue
      expect(find.text('2 of 3'), findsOneWidget);

      // Skip item 2 — cursor advances to 2
      await tester.tap(skipButton);
      await tester.pumpAndSettle();
      expect(find.text('Blinkit'), findsOneWidget);
      expect(find.text('3 of 3'), findsOneWidget);

      // No Inbox Zero — all 3 still in queue
      expect(find.text('Inbox Zero!'), findsNothing);
    });

    testWidgets('resolve removes item — Inbox Zero after confirming the only item',
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

      // Confirm (keep) the item — removes it from the queue
      final keepButton = find.byIcon(Icons.check_rounded);
      await tester.tap(keepButton);
      await tester.pump();

      expect(find.text('Inbox Zero!'), findsOneWidget);
    });

    testWidgets(
        'skip at last item does not crash and stays at last item',
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
      expect(find.text('1 of 1'), findsOneWidget);

      // Skip the only item — cursor stays at 0, item remains
      final skipButton = find.byIcon(Icons.skip_next_rounded);
      await tester.tap(skipButton);
      await tester.pumpAndSettle();

      // Still shows the item (not Inbox Zero)
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.text('Inbox Zero!'), findsNothing);
    });
  });
}
