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

void main() {
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
      categoryIcon: 'food',
      status: 'needs_review',
    );
  }

  Future<void> pumpScreen(
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

  testWidgets('shows Inbox Zero when review queue is empty', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('Inbox Zero!'), findsOneWidget);
  });

  testWidgets('renders top item in swipeable card stack', (tester) async {
    await pumpScreen(tester, [
      reviewItem(
        id: '1',
        displayName: 'Swiggy',
        counterpartyKey: 'raw:swiggy',
        categoryId: 'Food',
      ),
    ]);

    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
  });
}
