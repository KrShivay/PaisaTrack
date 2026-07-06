import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  TransactionListItem item({
    required String id,
    required DateTime ts,
    required double amount,
    required TransactionDirection direction,
  }) {
    return TransactionListItem(
      id: id,
      ts: ts,
      amount: amount,
      direction: direction,
      displayName: id,
      categoryName: null,
    );
  }

  testWidgets('sums this-month debit/credit totals and ignores other months',
      (tester) async {
    final now = DateTime.now().toUtc();
    final lastMonth = DateTime.utc(now.year, now.month - 1, 15);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionListProvider.overrideWith(
            (ref) => Stream.value([
              item(
                id: 'debit_1',
                ts: now,
                amount: 150,
                direction: TransactionDirection.debit,
              ),
              item(
                id: 'debit_2',
                ts: now,
                amount: 50,
                direction: TransactionDirection.debit,
              ),
              item(
                id: 'credit_1',
                ts: now,
                amount: 1000,
                direction: TransactionDirection.credit,
              ),
              item(
                id: 'debit_last_month',
                ts: lastMonth,
                amount: 9999,
                direction: TransactionDirection.debit,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Spent'), findsOneWidget);
    expect(find.text('₹200.00'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('₹1000.00'), findsOneWidget);
  });
}
