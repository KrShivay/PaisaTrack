import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/payment_source_repository.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
      'indexed SQL reconcileOwnedTransfers creates graph link and denormalized owned_transfer_id',
      () async {
    // Add 2 owned payment sources
    await database.into(database.paymentSources).insert(
          PaymentSourcesCompanion.insert(
            id: 'src_hdfc',
            kind: 'bank',
            maskedIdentifier: 'XX1234',
            isOwned: const Value(true),
            isActive: const Value(true),
            createdAt: DateTime.utc(2026, 7, 1),
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        );

    await database.into(database.paymentSources).insert(
          PaymentSourcesCompanion.insert(
            id: 'src_icici',
            kind: 'bank',
            maskedIdentifier: 'XX5678',
            isOwned: const Value(true),
            isActive: const Value(true),
            createdAt: DateTime.utc(2026, 7, 1),
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        );

    final ts = DateTime.utc(2026, 7, 10, 10, 0).millisecondsSinceEpoch;

    // Transaction 1: Debit on HDFC
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_leg1',
            ts: ts,
            amount: 5000.0,
            direction: 'debit',
            channel: 'netbanking',
            paymentSourceId: const Value('src_hdfc'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    // Transaction 2: Credit on ICICI (2 mins later)
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_leg2',
            ts: ts + 120000,
            amount: 5000.0,
            direction: 'credit',
            channel: 'netbanking',
            paymentSourceId: const Value('src_icici'),
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    final repo = PaymentSourceRepository(database);
    final pairs = await repo.reconcileOwnedTransfers();

    expect(pairs, 1);

    // Verify denormalized columns on transactions
    final txns = await database.select(database.transactions).get();
    expect(txns, hasLength(2));
    expect(txns[0].ownedTransferId, isNotNull);
    expect(txns[1].ownedTransferId, isNotNull);
    expect(txns[0].ownedTransferId, txns[1].ownedTransferId);

    // Verify graph link in transaction_links table
    final links = await database.select(database.transactionLinks).get();
    expect(links, hasLength(1));
    expect(links.first.linkType, 'transfer_leg');
    expect(links.first.basis, 'indexed_owned_transfer');
  });

  test('owned transfer matching abstains for equal or unknown source masks',
      () async {
    Future<void> source(String id, String mask) =>
        database.into(database.paymentSources).insert(
              PaymentSourcesCompanion.insert(
                id: id,
                kind: 'bank',
                maskedIdentifier: mask,
                isOwned: const Value(true),
                isActive: const Value(true),
                createdAt: DateTime.utc(2026, 7, 1),
                updatedAt: DateTime.utc(2026, 7, 1),
              ),
            );

    Future<void> transaction({
      required String id,
      required int time,
      required String direction,
      required String sourceId,
    }) =>
        database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: id,
                ts: time,
                amount: 5000,
                direction: direction,
                channel: 'netbanking',
                paymentSourceId: Value(sourceId),
                parseSource: 'generic',
                confidenceJson: '{}',
                status: 'auto',
                createdAt: DateTime.utc(2026, 7, 10),
                updatedAt: DateTime.utc(2026, 7, 10),
              ),
            );

    await source('equal_a', 'XX 1234');
    await source('equal_b', '**-1234');
    await source('unknown_a', 'XXXX');
    await source('unknown_b', 'XX9876');
    await source('different_a', 'XX5678');
    await source('different_b', 'XX4321');

    final base = DateTime.utc(2026, 7, 10).millisecondsSinceEpoch;
    await transaction(
      id: 'equal_debit',
      time: base,
      direction: 'debit',
      sourceId: 'equal_a',
    );
    await transaction(
      id: 'equal_credit',
      time: base + 60000,
      direction: 'credit',
      sourceId: 'equal_b',
    );
    await transaction(
      id: 'unknown_debit',
      time: base + 3 * 86400000,
      direction: 'debit',
      sourceId: 'unknown_a',
    );
    await transaction(
      id: 'unknown_credit',
      time: base + 3 * 86400000 + 60000,
      direction: 'credit',
      sourceId: 'unknown_b',
    );
    await transaction(
      id: 'different_debit',
      time: base + 6 * 86400000,
      direction: 'debit',
      sourceId: 'different_a',
    );
    await transaction(
      id: 'different_credit',
      time: base + 6 * 86400000 + 60000,
      direction: 'credit',
      sourceId: 'different_b',
    );

    expect(
      await PaymentSourceRepository(database).reconcileOwnedTransfers(),
      1,
    );
    final transactions = {
      for (final row in await database.select(database.transactions).get())
        row.id: row,
    };
    expect(transactions['equal_debit']!.ownedTransferId, equals(null));
    expect(transactions['equal_credit']!.ownedTransferId, equals(null));
    expect(transactions['unknown_debit']!.ownedTransferId, equals(null));
    expect(transactions['unknown_credit']!.ownedTransferId, equals(null));
    expect(transactions['different_debit']!.ownedTransferId, isNotNull);
    expect(
      transactions['different_debit']!.ownedTransferId,
      transactions['different_credit']!.ownedTransferId,
    );
  });
}
