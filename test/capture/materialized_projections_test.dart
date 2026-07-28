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

  test('indexed SQL reconcileOwnedTransfers creates graph link and denormalized owned_transfer_id', () async {
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
}
