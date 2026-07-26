import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/enrichment/counterparty_backfill_service.dart';

void main() {
  late AppDatabase database;
  late CounterpartyBackfillService service;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    service = CounterpartyBackfillService(database);

    final now = DateTime.utc(2026, 7, 10);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_bf_1',
            ts: now.millisecondsSinceEpoch,
            amount: 299,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('SWIGGY INSTAMART BANGALORE'),
            counterpartyVpa: const Value('swiggy@ybl'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  test('previewBackfill lists affected rows before write and leaves merchant_raw untouched', () async {
    final preview = await service.previewBackfill();
    expect(preview, hasLength(1));
    expect(preview.first.txnId, 'txn_bf_1');
    expect(preview.first.merchantRaw, 'SWIGGY INSTAMART BANGALORE');
    expect(preview.first.newIdentityKey, 'MERCHANT_SWIGGYINSTAMART');

    // Verify database row is untouched during preview
    final txn = await (database.select(database.transactions)..where((t) => t.id.equals('txn_bf_1'))).getSingle();
    expect(txn.merchantRaw, 'SWIGGY INSTAMART BANGALORE');
  });

  test('applyBackfill writes counterparties and undoBackfill restores prior state', () async {
    final preview = await service.previewBackfill();
    final result = await service.applyBackfill(preview);

    expect(result.affectedCount, 1);

    final counterparties = await database.select(database.counterparties).get();
    expect(counterparties, hasLength(1));
    expect(counterparties.first.identityKey, 'MERCHANT_SWIGGYINSTAMART');

    final undone = await service.undoBackfill(result.checkpointId);
    expect(undone, isTrue);

    // Verify raw source text remains untouched
    final txn = await (database.select(database.transactions)..where((t) => t.id.equals('txn_bf_1'))).getSingle();
    expect(txn.merchantRaw, 'SWIGGY INSTAMART BANGALORE');
  });
}
