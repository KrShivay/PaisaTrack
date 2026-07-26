import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('v9->v10 migration creates financial_events and transaction_links tables', () async {
    // Insert a transaction row
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1001',
            ts: 1783209600000,
            amount: 150.0,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1002',
            ts: 1783209610000,
            amount: 150.0,
            direction: 'credit',
            channel: 'upi',
            parseSource: 'generic',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 7, 10),
            updatedAt: DateTime.utc(2026, 7, 10),
          ),
        );

    // Insert a financial event
    await database.into(database.financialEvents).insert(
          FinancialEventsCompanion.insert(
            id: 'event_1',
            eventKey: 'key_swiggy_15000_1783209600',
            keyBasis: 'amount_merchant_window',
            kind: 'purchase',
            netAmountPaise: 15000,
            openedAt: 1783209600000,
          ),
        );

    final events = await database.select(database.financialEvents).get();
    expect(events, hasLength(1));
    expect(events.first.id, 'event_1');
    expect(events.first.netAmountPaise, 15000);
    expect(events.first.currency, 'INR');

    // Insert a transaction link referencing existing transactions
    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: 'link_1',
            fromTxnId: 'txn_1001',
            toTxnId: 'txn_1002',
            linkType: 'reverses',
            basis: 'utr_match',
            createdAt: 1783209610000,
          ),
        );

    final links = await database.select(database.transactionLinks).get();
    expect(links, hasLength(1));
    expect(links.first.fromTxnId, 'txn_1001');
    expect(links.first.toTxnId, 'txn_1002');
    expect(links.first.linkType, 'reverses');
  });

  test('financial_events enforces unique event_key', () async {
    await database.into(database.financialEvents).insert(
          FinancialEventsCompanion.insert(
            id: 'event_1',
            eventKey: 'key_unique',
            keyBasis: 'utr',
            kind: 'purchase',
            netAmountPaise: 5000,
            openedAt: 1783209600000,
          ),
        );

    expect(
      () => database.into(database.financialEvents).insert(
            FinancialEventsCompanion.insert(
              id: 'event_2',
              eventKey: 'key_unique',
              keyBasis: 'utr',
              kind: 'purchase',
              netAmountPaise: 5000,
              openedAt: 1783209600000,
            ),
          ),
      throwsException,
    );
  });
}
