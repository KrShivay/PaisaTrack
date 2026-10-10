import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/supporting_sms_classifier.dart';
import 'package:paisatrack/capture/supporting_sms_linker.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/expected_event_repository.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';

/// Synthetic data only.
void main() {
  late AppDatabase database;
  late SupportingSmsClassifier classifier;
  late SupportingSmsLinker linker;

  final txnAt = DateTime.utc(2026, 11, 5, 4);

  setUpAll(() {
    classifier = SupportingSmsClassifier.fromJson(
      File(SupportingSmsClassifier.assetPath).readAsStringSync(),
    );
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    linker = SupportingSmsLinker(database, classifier);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> addSms(String id, String body, DateTime at) {
    return database.into(database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: id,
            sender: 'AX-BANK',
            body: body,
            receivedAt: at,
            purgeAfter: at.add(const Duration(days: 7)),
          ),
        );
  }

  Future<void> addTxn(
    String id, {
    double amount = 12345,
    String direction = 'debit',
    DateTime? at,
    String? accountHint = 'xx1234',
    String? refId,
    String? vpa,
    String? merchant,
    String currency = 'INR',
    String lifecycle = 'settled',
    bool deleted = false,
    bool notTransaction = false,
    String? duplicateOf,
    String? smsId,
  }) async {
    final stamp = at ?? txnAt;
    if (smsId != null) {
      await addSms(smsId, 'Rs $amount debited', stamp);
    }
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: stamp.millisecondsSinceEpoch,
            amount: amount,
            currencyCode: Value(currency),
            currencySymbol: Value(currency == 'INR' ? '₹' : '\$'),
            direction: direction,
            channel: 'upi',
            accountHint: Value(accountHint),
            refId: Value(refId),
            counterpartyVpa: Value(vpa),
            merchantRaw: Value(merchant),
            parseSource: 'template',
            smsId: Value(smsId),
            confidenceJson: '{}',
            status: 'auto',
            lifecycleState: Value(lifecycle),
            isDeleted: Value(deleted),
            isNotTransaction: Value(notTransaction),
            duplicateOfTxnId: Value(duplicateOf),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  }

  Future<List<SmsTransactionLink>> links() =>
      database.select(database.smsTransactionLinks).get();

  const emiNotice =
      'Dear Customer, your loan EMI of Rs 12,345 is due on 05-Nov-26. '
      'Please maintain sufficient balance in A/c XX1234. -HDFC Bank';

  group('notice before the debit', () {
    test('linkTransaction attaches an earlier EMI notice', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 3)),);
      await addTxn('txn_a', smsId: 'sms_debit');

      expect(await linker.linkTransaction('txn_a'), 1);

      final link = (await links()).single;
      expect(link.smsId, 'sms_emi');
      expect(link.transactionId, 'txn_a');
      expect(link.kind, 'emi_notice');
      expect(link.basis, 'amount+window+account_suffix');
      expect(link.confidence, 1.0);
      // Idempotent.
      expect(await linker.linkTransaction('txn_a'), 0);
      expect(await links(), hasLength(1));
    });

    test('linkMessage finds the transaction when the notice arrives last',
        () async {
      await addTxn('txn_a', smsId: 'sms_debit');
      await addSms('sms_emi', emiNotice, txnAt.add(const Duration(hours: 2)));

      expect(await linker.linkMessage('sms_emi'), 1);
      expect((await links()).single.transactionId, 'txn_a');
    });
  });

  group('rules', () {
    test('requires a corroborator', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_a', accountHint: 'xx9999');
      expect(await linker.linkMessage('sms_emi'), 0);
      expect(await links(), isEmpty);
    });

    test('requires the exact amount in paise', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_a', amount: 12345.01);
      await addTxn('txn_b', amount: 12344.99);
      expect(await linker.linkMessage('sms_emi'), 0);
    });

    test('requires the same source-currency bucket', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_usd', currency: 'USD');
      expect(await linker.linkMessage('sms_emi'), 0);
    });

    test('notices reach back 7 days but not 8', () async {
      await addTxn('txn_a');
      await addSms(
        'sms_in',
        emiNotice,
        txnAt.subtract(const Duration(days: 6, hours: 20)),
      );
      await addSms(
        'sms_out',
        emiNotice.replaceAll('05-Nov-26', '04-Nov-26'),
        txnAt.subtract(const Duration(days: 8)),
      );
      expect(await linker.linkMessage('sms_in'), 1);
      expect(await linker.linkMessage('sms_out'), 0);
    });

    test('a due date far from the debit vetoes the link', () async {
      await addTxn('txn_a');
      await addSms(
        'sms_far',
        emiNotice.replaceAll('05-Nov-26', '25-Nov-26'),
        txnAt.subtract(const Duration(days: 2)),
      );
      expect(await linker.linkMessage('sms_far'), 0);
    });

    test('abstains when more than one transaction qualifies', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 2)),);
      await addTxn('txn_a');
      await addTxn('txn_b', at: txnAt.add(const Duration(days: 1)));
      expect(await linker.linkMessage('sms_emi'), 0);
      expect(await linker.linkTransaction('txn_a'), 0);
      expect(await links(), isEmpty);
    });

    test('never links deleted, not-a-transaction or unsettled rows', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_del', deleted: true);
      await addTxn('txn_not', notTransaction: true);
      await addTxn('txn_pending', lifecycle: 'pending');
      expect(await linker.linkMessage('sms_emi'), 0);
      expect(await linker.linkTransaction('txn_del'), 0);
      expect(await linker.linkTransaction('txn_not'), 0);
      expect(await linker.linkTransaction('txn_pending'), 0);
    });

    test('a duplicate row is skipped in favour of its canonical row', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_canon');
      await addTxn('txn_dup', duplicateOf: 'txn_canon');
      expect(await linker.linkMessage('sms_emi'), 1);
      expect((await links()).single.transactionId, 'txn_canon');
    });

    test('a debit SMS that is itself a transaction source is not supporting',
        () async {
      await addTxn(
        'txn_a',
        smsId: 'sms_primary',
      );
      await database.update(database.rawSms).write(
            const RawSmsCompanion(
              body: Value(
                'Rs 12,345.00 debited from A/c XX1234 towards your loan EMI on '
                '05-Nov-26.',
              ),
            ),
          );
      expect(await linker.linkMessage('sms_primary'), 0);
      expect(await linker.linkTransaction('txn_a'), 0);
    });

    test('an SMS already linked is not linked again elsewhere', () async {
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 1)),);
      await addTxn('txn_a');
      expect(await linker.linkMessage('sms_emi'), 1);
      await addTxn('txn_b', at: txnAt.add(const Duration(days: 1)));
      expect(await linker.linkMessage('sms_emi'), 0);
      expect(await linker.linkTransaction('txn_b'), 0);
      expect(await links(), hasLength(1));
    });
  });

  group('dividend and RD advices', () {
    test('dividend matches a company token in the bank narration', () async {
      await addTxn(
        'txn_div',
        amount: 1250,
        direction: 'credit',
        accountHint: null,
        merchant: 'ACH C- ACME INDUSTRIES LTD',
      );
      await addSms(
        'sms_div',
        'Dividend of Rs.1,250.00 from ACME INDUSTRIES LTD has been paid to '
            'your bank account. -KFINTECH',
        txnAt.add(const Duration(days: 2)),
      );
      expect(await linker.linkMessage('sms_div'), 1);
      final link = (await links()).single;
      expect(link.kind, 'dividend');
      expect(link.basis, 'amount+window+company_token');
    });

    test('dividend window is plus or minus 3 days', () async {
      await addTxn(
        'txn_div',
        amount: 1250,
        direction: 'credit',
        accountHint: 'xx4321',
      );
      const body = 'Dividend of Rs.1,250.00 credited to your A/c XX4321 by '
          'ACME INDUSTRIES LTD';
      await addSms('sms_late', body, txnAt.add(const Duration(days: 4)));
      await addSms('sms_ok', body, txnAt.subtract(const Duration(days: 2)));
      expect(await linker.linkMessage('sms_late'), 0);
      expect(await linker.linkMessage('sms_ok'), 1);
    });

    test('RD instalment must be a debit and matches by account suffix',
        () async {
      await addTxn('txn_rd', amount: 5000, accountHint: 'xx1234');
      await addTxn(
        'txn_credit',
        amount: 5000,
        direction: 'credit',
        accountHint: 'xx1234',
      );
      await addSms(
        'sms_rd',
        'Rs 5,000.00 debited from A/c XX1234 on 05-Nov-26 towards RD A/c '
            '3300112233 instalment.',
        txnAt,
      );
      expect(await linker.linkMessage('sms_rd'), 1);
      final link = (await links()).single;
      expect(link.transactionId, 'txn_rd');
      expect(link.kind, 'rd_instalment');
    });
  });

  group('collect requests', () {
    test('match by VPA and reference corroborators', () async {
      await addTxn(
        'txn_pay',
        amount: 250,
        accountHint: null,
        vpa: 'abc.shop@ybl',
      );
      await addSms(
        'sms_req',
        'Payment request of INR 250.00 from abc.shop@ybl received on '
            'PhonePe.',
        txnAt.subtract(const Duration(hours: 5)),
      );
      expect(await linker.linkMessage('sms_req'), 1);
      expect((await links()).single.basis, 'amount+window+counterparty');

      await addTxn('txn_ref',
          amount: 500, accountHint: null, refId: 'R12345678',);
      await addSms(
        'sms_ref',
        'Someone has requested Rs 500.00 from you via UPI. Ref R12345678',
        txnAt.subtract(const Duration(hours: 5)),
      );
      expect(await linker.linkMessage('sms_ref'), 1);
    });

    test('a request for a different payee does not link', () async {
      await addTxn(
        'txn_pay',
        amount: 250,
        accountHint: null,
        vpa: 'other@ybl',
      );
      await addSms(
        'sms_req',
        'Payment request of INR 250.00 from abc.shop@ybl received.',
        txnAt.subtract(const Duration(hours: 5)),
      );
      expect(await linker.linkMessage('sms_req'), 0);
    });
  });

  group('retention and backfill', () {
    test('a linked supporting SMS survives the purge, unlinked ones expire',
        () async {
      final received = txnAt.subtract(const Duration(days: 2));
      await addSms('sms_linked', emiNotice, received);
      await addSms('sms_unlinked', 'old unrelated', received);
      await addTxn('txn_a');
      await linker.linkMessage('sms_linked');

      await RawSmsRetention.purgeExpiredUnlinked(
        database,
        now: txnAt.add(const Duration(days: 30)),
      );

      final kept = (await database.select(database.rawSms).get())
          .map((row) => row.id)
          .toSet();
      expect(kept, {'sms_linked'});
    });

    test('backfill links existing retained SMS once and is idempotent',
        () async {
      await addTxn('txn_a', smsId: 'sms_debit');
      await addSms(
          'sms_emi', emiNotice, txnAt.subtract(const Duration(days: 2)),);
      await addSms('sms_noise', 'Your OTP is 123456', txnAt);

      expect(await linker.backfill(), 1);
      expect(await linker.backfill(), 0);
      expect((await links()).single.smsId, 'sms_emi');
    });

    test('backfill records the origin SMS of fulfilled expected events',
        () async {
      await addTxn('txn_a');
      await addSms(
        'sms_origin',
        'Reminder: payment of Rs 700 is due on 05-Nov-26.',
        txnAt.subtract(const Duration(days: 2)),
      );
      await database.into(database.expectedEvents).insert(
            ExpectedEventsCompanion.insert(
              id: 'ee_1',
              source: 'sms_reminder',
              originSmsId: const Value('sms_origin'),
              label: 'Bill',
              expectedAmountPaise: 70000,
              expectedDate: DateTime.utc(2026, 11, 5),
              state: 'fulfilled',
              fulfilledTxnId: const Value('txn_a'),
              confidence: 1,
              dedupKey: 'bill',
            ),
          );

      await linker.backfill();

      final link = (await links()).single;
      expect(link.smsId, 'sms_origin');
      expect(link.transactionId, 'txn_a');
      expect(link.kind, 'related');
      expect(link.basis, 'expected_event_fulfilled');
    });

    test('reconciliation links the origin SMS when an event is fulfilled',
        () async {
      await addSms(
        'sms_origin',
        'Reminder: your loan EMI of Rs 12,345 is due on 05-Nov-26.',
        txnAt.subtract(const Duration(days: 2)),
      );
      await addTxn('txn_a', vpa: 'lender@upi');
      final repository = ExpectedEventRepository(
        database,
        supportingClassifier: classifier,
      );
      await repository.recordExpectedEvent(
        source: 'sms_reminder',
        originSmsId: 'sms_origin',
        counterpartyId: 'lender@upi',
        label: 'Lender',
        expectedAmountPaise: 1234500,
        currencyCode: 'INR',
        currencySymbol: '₹',
        expectedDate: DateTime.utc(2026, 11, 5),
        confidence: 0.95,
      );
      await database.update(database.transactions).write(
            const TransactionsCompanion(status: Value('auto')),
          );

      await repository.reconcileExpectedEvents(
          today: DateTime.utc(2026, 11, 5),);

      final link = (await links()).single;
      expect(link.smsId, 'sms_origin');
      expect(link.kind, 'emi_notice');
      expect(link.basis, 'expected_event_fulfilled');
    });
  });
}
