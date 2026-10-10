import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/transaction_sms_repository.dart';

void main() {
  late AppDatabase database;
  late TransactionSmsRepository repository;
  final base = DateTime.utc(2026, 11, 5, 5);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TransactionSmsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> sms(String id, Duration offset) {
    final at = base.add(offset);
    return database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: id,
            sender: 'BANK',
            body: 'body $id',
            receivedAt: at,
            purgeAfter: at.add(const Duration(days: 7)),
          ),
        );
  }

  Future<void> txn(String id, {String? smsId, String? duplicateOf}) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: base.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            smsId: Value(smsId),
            duplicateOfTxnId: Value(duplicateOf),
            confidenceJson: '{}',
            status: 'auto',
            createdAt: base,
            updatedAt: base,
          ),
        );
  }

  Future<void> link(String smsId, String txnId, String kind) {
    return database.into(database.smsTransactionLinks).insert(
          SmsTransactionLinksCompanion.insert(
            smsId: smsId,
            transactionId: txnId,
            kind: kind,
            basis: 'test',
            createdAt: base,
          ),
        );
  }

  test('orders primary, duplicates, then supporting by receive time', () async {
    await sms('p', Duration.zero);
    await sms('d_late', const Duration(minutes: 9));
    await sms('d_early', const Duration(minutes: 2));
    await sms('s_late', const Duration(days: -1));
    await sms('s_early', const Duration(days: -3));
    await txn('canon', smsId: 'p');
    await txn('dup_late', smsId: 'd_late', duplicateOf: 'canon');
    await txn('dup_early', smsId: 'd_early', duplicateOf: 'canon');
    await link('s_late', 'canon', 'collect_request');
    await link('s_early', 'canon', 'emi_notice');

    final messages = await repository.messagesFor('canon');

    expect(messages.map((m) => m.smsId), [
      'p',
      'd_early',
      'd_late',
      's_early',
      's_late',
    ]);
    expect(messages.map((m) => m.role), [
      TransactionSmsRole.primary,
      TransactionSmsRole.duplicate,
      TransactionSmsRole.duplicate,
      TransactionSmsRole.supporting,
      TransactionSmsRole.supporting,
    ]);
    expect(messages.map((m) => m.kind), [
      null,
      null,
      null,
      'emi_notice',
      'collect_request',
    ]);
    expect(messages.first.body, 'body p');
    expect(messages.first.sender, 'BANK');
  });

  test('a duplicate row shows its canonical SMS and the canonical links',
      () async {
    await sms('p', Duration.zero);
    await sms('d', const Duration(minutes: 1));
    await sms('s', const Duration(days: -1));
    await txn('canon', smsId: 'p');
    await txn('dup', smsId: 'd', duplicateOf: 'canon');
    await link('s', 'canon', 'dividend');

    final messages = await repository.messagesFor('dup');

    expect(messages.map((m) => (m.smsId, m.role)), [
      ('d', TransactionSmsRole.primary),
      ('p', TransactionSmsRole.duplicate),
      ('s', TransactionSmsRole.supporting),
    ]);
  });

  test('skips purged raw SMS, de-duplicates by id, and handles no rows',
      () async {
    await sms('p', Duration.zero);
    await txn('t', smsId: 'p');
    await link('p', 't', 'related');
    await link('gone', 't', 'related');

    final messages = await repository.messagesFor('t');

    expect(messages.map((m) => (m.smsId, m.role)), [
      ('p', TransactionSmsRole.primary),
    ]);
    expect(await repository.messagesFor('missing'), isEmpty);
    await txn('bare');
    expect(await repository.messagesFor('bare'), isEmpty);
  });

  test('recordLink is idempotent', () async {
    await txn('t');
    expect(
      await repository.recordLink(
        smsId: 's',
        transactionId: 't',
        kind: 'related',
        basis: 'a',
      ),
      isTrue,
    );
    expect(
      await repository.recordLink(
        smsId: 's',
        transactionId: 't',
        kind: 'dividend',
        basis: 'b',
      ),
      isFalse,
    );
    final rows = await database.select(database.smsTransactionLinks).get();
    expect(rows.single.kind, 'related');
  });
}
