import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertTxn({
    required String id,
    required DateTime ts,
    required double amount,
    required String direction,
    bool isDeleted = false,
  }) {
    return database.into(database.transactions).insertOnConflictUpdate(
          TransactionsCompanion.insert(
            id: id,
            ts: ts.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            isDeleted: Value(isDeleted),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  }

  testWidgets('sums this-month debit/credit totals and ignores other months '
      'and soft-deleted rows', (tester) async {
    final now = DateTime.now().toUtc();
    final lastMonth = DateTime.utc(now.year, now.month - 1, 15);

    await insertTxn(id: 'debit_1', ts: now, amount: 150, direction: 'debit');
    await insertTxn(id: 'debit_2', ts: now, amount: 50, direction: 'debit');
    await insertTxn(id: 'credit_1', ts: now, amount: 1000, direction: 'credit');
    await insertTxn(
      id: 'debit_last_month',
      ts: lastMonth,
      amount: 9999,
      direction: 'debit',
    );
    await insertTxn(
      id: 'debit_deleted',
      ts: now,
      amount: 7777,
      direction: 'debit',
      isDeleted: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spent'), findsOneWidget);
    expect(find.text('₹200.00'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('₹1000.00'), findsOneWidget);

    // flutter_test disposes the widget tree (and drift's watch() stream)
    // before any tearDown/addTearDown callback runs, so close() must happen
    // here, before the test body returns, or drift's markAsClosed() schedules
    // a debounce Timer.run that outlives the test — see the comment in
    // drift's StreamQueryStore.markAsClosed.
    await database.close();
  });
}
