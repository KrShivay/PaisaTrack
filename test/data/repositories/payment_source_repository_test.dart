import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/payment_source_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

void main() {
  late AppDatabase database;
  late PaymentSourceRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = PaymentSourceRepository(database);
    // Force beforeOpen so the source-link trigger exists before inserts.
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() => database.close());

  Future<void> insertTransaction({
    required String id,
    required String direction,
    required String accountHint,
    required DateTime timestamp,
    double amount = 500,
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: timestamp.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'upi',
            accountHint: Value(accountHint),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
  }

  test('trigger links sources and unique owned transfer pairs are recognized',
      () async {
    final timestamp = DateTime.utc(2026, 7, 16, 10);
    await insertTransaction(
      id: 'debit',
      direction: 'debit',
      accountHint: 'xx1111',
      timestamp: timestamp,
    );
    await insertTransaction(
      id: 'credit',
      direction: 'credit',
      accountHint: 'xx2222',
      timestamp: timestamp.add(const Duration(minutes: 4)),
    );

    final sources = await database.select(database.paymentSources).get();
    expect(sources, hasLength(2));
    expect(sources.every((source) => source.isOwned), isTrue);
    expect(
      (await database.select(database.transactions).get())
          .every((transaction) => transaction.paymentSourceId != null),
      isTrue,
    );

    expect(await repository.reconcileOwnedTransfers(), 1);
    final linked = await database.select(database.transactions).get();
    expect(linked.map((row) => row.ownedTransferId).toSet(), hasLength(1));
    expect(linked.first.ownedTransferId, isNotNull);
  });

  test('nickname and analytics exclusion propagate without hiding rows',
      () async {
    final timestamp = DateTime.utc(2026, 7, 16, 10);
    await insertTransaction(
      id: 'txn',
      direction: 'debit',
      accountHint: 'xx3333',
      timestamp: timestamp,
    );
    final source = await database.select(database.paymentSources).getSingle();

    await repository.updateSource(
      sourceId: source.id,
      nickname: const Value('Daily card'),
      institution: const Value('Example Bank'),
      includeInAnalytics: const Value(false),
      isActive: const Value(false),
      clock: () => timestamp.add(const Duration(hours: 1)),
    );

    final updatedSource =
        await database.select(database.paymentSources).getSingle();
    final updatedTransaction =
        await database.select(database.transactions).getSingle();
    expect(updatedSource.nickname, 'Daily card');
    expect(updatedSource.institution, 'Example Bank');
    expect(updatedSource.isActive, isFalse);
    expect(updatedSource.includeInAnalytics, isFalse);
    expect(updatedTransaction.isAnalyticsExcluded, isTrue);

    final visible =
        await TransactionRepository(database).watchTransactions().first;
    expect(visible, hasLength(1));
    expect(visible.single.paymentSourceName, 'Daily card');
    expect(visible.single.includeInAnalytics, isFalse);
  });
}
