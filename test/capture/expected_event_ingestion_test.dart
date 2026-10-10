import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/expected_event_repository.dart';

void main() {
  late AppDatabase database;
  late SmsIngestor ingestor;
  late ExpectedEventRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ExpectedEventRepository(database);
    final parser = ParserCascade(
      templateMatcher: TemplateMatcher(
        registries: const [],
        trustLedger: TemplateTrustLedger(database),
      ),
    );
    final classifier = MessageKindClassifier.fromJson(
      File('assets/seed/message_cues_in.json').readAsStringSync(),
    );
    ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: classifier,
      expectedEventRepository: repository,
      financialCalendar:
          const FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
      'Three reminders for the same bill produce exactly 1 expected event and 0 transactions',
      () async {
    final now = DateTime.utc(2026, 7, 10);
    final sms1 = RawSms(
      id: 'sms_rem_1',
      sender: 'HDFCBK',
      body: 'Reminder: Your credit card bill of Rs 4500 is due on 15-Jul-2026.',
      receivedAt: now,
    );
    final sms2 = RawSms(
      id: 'sms_rem_2',
      sender: 'HDFCBK',
      body:
          'Reminder 2: Your credit card bill of Rs 4500 is due on 15-Jul-2026.',
      receivedAt: now,
    );
    final sms3 = RawSms(
      id: 'sms_rem_3',
      sender: 'HDFCBK',
      body:
          'Final Reminder: Your credit card bill of Rs 4500 is due on 15-Jul-2026.',
      receivedAt: now,
    );

    await ingestor.ingest(sms1);
    await ingestor.ingest(sms2);
    await ingestor.ingest(sms3);

    // AC: 3 reminders produce 1 expected event
    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.first.expectedAmountPaise, 450000);
    expect(events.first.currencyCode, 'INR');
    expect(events.first.currencySymbol, '₹');
    expect(events.first.label, contains('HDFCBK'));
    expect(
      events.first.expectedDate.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 15).millisecondsSinceEpoch,
    );

    // AC: A reminder NEVER creates a transaction
    final txns = await database.select(database.transactions).get();
    expect(txns, isEmpty);
  });

  test('comma-formatted reminder amount is parsed as a whole amount', () async {
    final sms = RawSms(
      id: 'sms_rem_comma',
      sender: 'HDFCBK',
      body:
          'Reminder: Your credit card bill of Rs 1,250 is due on 15-Jul-2026.',
      receivedAt: DateTime.utc(2026, 7, 10),
    );

    await ingestor.ingest(sms);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.single.expectedAmountPaise, 125000);
    expect(events.single.currencyCode, 'INR');
    expect(
      events.single.expectedDate.millisecondsSinceEpoch,
      DateTime.utc(2026, 7, 15).millisecondsSinceEpoch,
    );
  });

  test('USD reminders preserve source currency without matching INR spending',
      () async {
    final now = DateTime.utc(2026, 7, 10);
    await ingestor.ingest(
      RawSms(
        id: 'sms_rem_usd',
        sender: 'FOREIGN-SERVICE',
        body: 'Reminder: charge of USD 45.00 is due on 15-Jul-2026.',
        receivedAt: now,
      ),
    );

    final event = (await repository.getExpectedEvents()).single;
    expect(event.expectedAmountPaise, 4500);
    expect(event.currencyCode, 'USD');
    expect(event.currencySymbol, r'$');
  });

  test('comma-formatted reminder range preserves both bounds', () async {
    final sms = RawSms(
      id: 'sms_rem_range',
      sender: 'UTILITY',
      body: 'Reminder: upcoming charge may be 1,234,567 to 2,500,000 INR.',
      receivedAt: DateTime.utc(2026, 7, 10),
    );

    await ingestor.ingest(sms);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.single.amountLowPaise, 123456700);
    expect(events.single.amountHighPaise, 250000000);
    expect(
      events.single.expectedDate.millisecondsSinceEpoch,
      sms.receivedAt.millisecondsSinceEpoch,
    );
  });

  test('received-at fallback uses the financial calendar day', () async {
    await ingestor.ingest(
      RawSms(
        id: 'sms_rem_local_day',
        sender: 'UTILITY',
        body: 'Reminder: upcoming monthly bill Rs 4500.',
        receivedAt: DateTime.utc(2026, 7, 9, 20),
      ),
    );

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.single.expectedDate.toUtc(), DateTime.utc(2026, 7, 10));
  });

  test('rupee symbol and Indian grouping parse through the same normalizer',
      () async {
    final sms = RawSms(
      id: 'sms_rem_inr_symbol',
      sender: 'HDFCBK',
      body: 'Reminder: payment of ₹ 12,34,567 is due on 15-Jul-2026.',
      receivedAt: DateTime.utc(2026, 7, 10),
    );

    await ingestor.ingest(sms);

    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.single.expectedAmountPaise, 123456700);
  });

  test(
      'ingesting a reminder reconciles it with an earlier exact-identity debit',
      () async {
    final expectedDate = DateTime.utc(2026, 7, 10);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'prior_debit',
            ts: expectedDate.millisecondsSinceEpoch,
            amount: 4500,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            direction: 'debit',
            channel: 'upi',
            counterpartyVpa: const Value('billpay@upi'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: expectedDate,
            updatedAt: expectedDate,
          ),
        );
    final reminderIngestor = SmsIngestor(
      database: database,
      parser: ParserCascade(
        templateMatcher: TemplateMatcher(
          registries: [
            TemplateRegistry(
              senderPatterns: [RegExp(r'^BILLER$')],
              templates: [
                SmsTemplate(
                  id: 'reminder_with_vpa',
                  regex: RegExp(
                    r'Reminder: Rs (?<amount>\d+) due to (?<merchant>Electricity) (?<vpa>billpay@upi)',
                  ),
                  direction: 'debit',
                  channel: 'upi',
                  dateFormat: null,
                ),
              ],
            ),
          ],
        ),
      ),
      messageKindClassifier: MessageKindClassifier.fromJson(
        File('assets/seed/message_cues_in.json').readAsStringSync(),
      ),
      now: () => expectedDate,
    );

    await reminderIngestor.ingest(
      RawSms(
        id: 'identity_reminder',
        sender: 'BILLER',
        body: 'Reminder: Rs 4500 due to Electricity billpay@upi',
        receivedAt: expectedDate,
      ),
    );

    final event = (await repository.getExpectedEvents()).single;
    expect(event.state, 'fulfilled');
    expect(event.counterpartyId, 'billpay@upi');
    expect(event.fulfilledTxnId, 'prior_debit');
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test('snoozed obligations reconcile at the rescheduled expected date',
      () async {
    final due = DateTime.utc(2026, 7, 1);
    await repository.recordExpectedEvent(
      source: 'sms_reminder',
      originSmsId: 'snoozed_origin',
      counterpartyId: 'utility@upi',
      label: 'Utility bill',
      expectedAmountPaise: 12500,
      currencyCode: 'INR',
      currencySymbol: '₹',
      expectedDate: due,
      dateWindowDays: 0,
      confidence: 0.9,
    );
    final beforeSnooze = (await repository.getExpectedEvents()).single;
    await repository.snoozeEvent(beforeSnooze.id, days: 2);
    final rescheduledDate = DateTime.utc(2026, 7, 3);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'snoozed_payment',
            ts: rescheduledDate.millisecondsSinceEpoch,
            amount: 125,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            direction: 'debit',
            channel: 'upi',
            lifecycleState: const Value('settled'),
            status: 'confirmed',
            counterpartyVpa: const Value('UTILITY@UPI'),
            parseSource: 'template',
            confidenceJson: '{}',
            createdAt: rescheduledDate,
            updatedAt: rescheduledDate,
          ),
        );

    await repository.reconcileExpectedEvents(today: rescheduledDate);

    final event = (await repository.getExpectedEvents()).single;
    expect(event.expectedDate.toUtc(), rescheduledDate);
    expect(event.state, 'fulfilled');
    expect(event.fulfilledTxnId, 'snoozed_payment');
  });

  test('missing identity and invalid obligation amounts stay unresolved',
      () async {
    final oldDueDate = DateTime.utc(2026, 6, 1);
    Future<void> addExpected({
      required String label,
      required String? counterpartyId,
      required int expectedAmountPaise,
      int? amountLowPaise,
      int? amountHighPaise,
    }) =>
        repository.recordExpectedEvent(
          source: 'sms_reminder',
          label: label,
          counterpartyId: counterpartyId,
          expectedAmountPaise: expectedAmountPaise,
          amountLowPaise: amountLowPaise,
          amountHighPaise: amountHighPaise,
          currencyCode: 'INR',
          currencySymbol: '₹',
          expectedDate: oldDueDate,
          dateWindowDays: 0,
          confidence: 0.9,
        );

    await addExpected(
      label: 'No counterparty',
      counterpartyId: null,
      expectedAmountPaise: 10000,
    );
    await addExpected(
      label: 'Zero amount',
      counterpartyId: 'zero@upi',
      expectedAmountPaise: 0,
    );
    await addExpected(
      label: 'Invalid range',
      counterpartyId: 'range@upi',
      expectedAmountPaise: 10000,
      amountLowPaise: 20000,
      amountHighPaise: 5000,
    );

    await repository.reconcileExpectedEvents(today: DateTime.utc(2026, 7, 1));

    expect(
      (await repository.getExpectedEvents()).map((event) => event.state),
      everyElement('expected'),
    );
  });
}
