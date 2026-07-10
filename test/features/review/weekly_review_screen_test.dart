import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
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

  testWidgets('renders queued transactions for review', (tester) async {
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
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('-₹1,299.00'), findsOneWidget);
  });

  testWidgets(
      'low-trust review rows offer a parse verdict before category correction',
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

    await tester.tap(find.text('Bookstore'));
    await tester.pumpAndSettle();

    expect(find.text('Parsed correctly?'), findsOneWidget);
    expect(find.text('Confirm parse'), findsOneWidget);
    expect(find.text('Fix parse'), findsOneWidget);
  });
}
