import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
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
      categoryIcon: categoryIcon ?? 'food',
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
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows an empty state with no transactions', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No transactions found'), findsOneWidget);
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

    expect(find.text('Salary Inc'), findsOneWidget);
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.byType(BloomAmount), findsWidgets);
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
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Amazon'), findsWidgets);
    expect(find.text('Salary Inc'), findsNothing);
  });
}
