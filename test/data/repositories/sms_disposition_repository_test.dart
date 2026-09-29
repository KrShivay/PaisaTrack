import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_repository.dart';
import 'package:paisatrack/data/repositories/sms_disposition_repository.dart';
import 'package:paisatrack/intelligence/recurring_detector.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('disposition survives raw expiry and can be restored after restart',
      () async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_synthetic_1',
            sender: 'synthetic-bank',
            body: 'Synthetic body used only by this test',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_synthetic_1',
            ts: now.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: const Value('Synthetic Payee'),
            counterpartyVpa: const Value('synthetic@upi'),
            smsId: const Value('sms_synthetic_1'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.expectedEvents).insert(
          ExpectedEventsCompanion.insert(
            id: 'event_synthetic_1',
            source: 'test',
            label: 'Synthetic bill',
            counterpartyId: const Value('synthetic@upi'),
            expectedAmountPaise: 10000,
            expectedDate: today,
            state: 'fulfilled',
            fulfilledTxnId: const Value('txn_synthetic_1'),
            confidence: 1,
            dedupKey: 'synthetic_test',
          ),
        );
    final repo = SmsDispositionRepository(database);
    final transaction =
        await database.select(database.transactions).getSingle();

    await repo.markNotTransaction(transaction);
    expect(
      (await database.select(database.transactions).getSingle())
          .isNotTransaction,
      isTrue,
    );
    final reopened = await database.select(database.expectedEvents).getSingle();
    expect(reopened.state, 'expected');
    expect(reopened.fulfilledTxnId, isNull);
    expect(await database.select(database.payeeEvidence).get(), isEmpty);

    // Model retention expiry without deleting any physical device data.
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('txn_synthetic_1')))
        .write(const TransactionsCompanion(smsId: Value(null)));
    await database.delete(database.rawSms).go();

    final afterRestart = SmsDispositionRepository(database);
    final marked = await afterRestart.listMarkedTransactions();
    expect(marked, hasLength(1));
    expect(marked.single.smsId, 'sms_synthetic_1');
    await afterRestart.restore(marked.single.smsId);

    final restored = await database.select(database.transactions).getSingle();
    expect(restored.isNotTransaction, isFalse);
    expect(restored.smsId, isNull);
    expect(await database.select(database.smsDispositions).get(), isEmpty);
    expect(await database.select(database.payeeEvidence).get(), hasLength(2));
    expect(
      (await database.select(database.expectedEvents).getSingle()).state,
      'fulfilled',
    );
  });

  test('rebuild preserves a user-paused recurring series status', () async {
    final now = DateTime.now().toUtc();
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_synthetic_recurring',
            canonicalName: 'Synthetic recurring merchant',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    final dates = [
      DateTime.utc(now.year, now.month - 4, 1),
      DateTime.utc(now.year, now.month - 3, 1),
      DateTime.utc(now.year, now.month - 2, 1),
      DateTime.utc(now.year, now.month - 1, 1),
    ];
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_recurring_synthetic',
            sender: 'synthetic-bank',
            body: 'Synthetic body',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    for (var index = 0; index < dates.length; index++) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'txn_recurring_$index',
              ts: dates[index].millisecondsSinceEpoch,
              amount: 499,
              direction: 'debit',
              channel: 'card',
              merchantId: const Value('merchant_synthetic_recurring'),
              smsId: index == 0
                  ? const Value('sms_recurring_synthetic')
                  : const Value.absent(),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: dates[index],
              updatedAt: dates[index],
            ),
          );
    }
    await RecurringDetector(database).run(today: now);
    final series = await database.select(database.recurringSeries).getSingle();
    await RecurringRepository(database).setStatus(
      seriesId: series.id,
      status: 'paused',
    );

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_recurring_0')))
        .getSingle();
    await SmsDispositionRepository(database).markNotTransaction(transaction);

    final rebuilt = await database.select(database.recurringSeries).getSingle();
    expect(rebuilt.merchantId, series.merchantId);
    expect(rebuilt.id, isNot(series.id));
    expect(rebuilt.status, 'paused');

    await SmsDispositionRepository(database).restore('sms_recurring_synthetic');
    final restored =
        await database.select(database.recurringSeries).getSingle();
    expect(restored.id, series.id);
    expect(restored.status, 'paused');
  });
}
