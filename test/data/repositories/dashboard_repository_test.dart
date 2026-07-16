import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
  });

  tearDown(() => database.close());

  Future<void> insert(
    String id,
    DateTime timestamp,
    double amount, {
    String direction = 'debit',
    String? categoryId = 'food_dining',
    bool analyticsExcluded = false,
    String? ownedTransferId,
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: timestamp.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'upi',
            categoryId: Value(categoryId),
            merchantRaw: const Value('TEST MERCHANT'),
            parseSource: 'manual',
            confidenceJson: '{}',
            status: 'confirmed',
            isAnalyticsExcluded: Value(analyticsExcluded),
            ownedTransferId: Value(ownedTransferId),
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
  }

  test('dashboard SQL aggregates preserve analytics inclusion semantics',
      () async {
    await insert('current_debit', DateTime(2026, 7, 10), 100);
    await insert(
      'current_credit',
      DateTime(2026, 7, 11),
      500,
      direction: 'credit',
      categoryId: 'income',
    );
    await insert('previous_debit', DateTime(2026, 6, 10), 50);
    await insert(
      'transfer',
      DateTime(2026, 7, 12),
      1000,
      categoryId: 'transfers',
    );
    await insert(
      'excluded',
      DateTime(2026, 7, 13),
      900,
      analyticsExcluded: true,
    );
    await insert(
      'owned_transfer',
      DateTime(2026, 7, 14),
      800,
      ownedTransferId: 'pair_1',
    );

    final snapshot = await DashboardRepository(database).load(
      DashboardQueryWindow(
        start: DateTime(2026, 7),
        end: DateTime(2026, 8),
        previousStart: DateTime(2026, 6),
        previousEnd: DateTime(2026, 7),
        trendStart: DateTime(2026, 2),
        trendEnd: DateTime(2026, 8),
      ),
    );

    expect(snapshot.debitTotal, 100);
    expect(snapshot.creditTotal, 500);
    expect(snapshot.previousSpend, 50);
    expect(snapshot.categories.single.total, 100);
    expect(snapshot.merchants.single.total, 100);
    expect(snapshot.merchants.single.count, 1);
    expect(snapshot.trendByMonth['2026-06'], 50);
    expect(snapshot.trendByMonth['2026-07'], 100);
  });

  test('transaction feed enforces limit and optional date bounds', () async {
    for (var day = 1; day <= 5; day++) {
      await insert('txn_$day', DateTime(2026, 7, day), day.toDouble());
    }

    final items = await TransactionRepository(database)
        .watchTransactions(
          limit: 2,
          start: DateTime(2026, 7, 2),
          end: DateTime(2026, 7, 5),
        )
        .first;

    expect(items.map((item) => item.id), ['txn_4', 'txn_3']);
  });
}
