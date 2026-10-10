import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/supporting_sms_classifier.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/transaction_sms_repository.dart';

/// End-to-end ingestion of supporting SMS using only synthetic messages.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase database;
  late SmsIngestor ingestor;

  SmsIngestor build({required bool withSupporting}) => SmsIngestor(
        database: database,
        parser: const ParserCascade(
          templateMatcher: TemplateMatcher(registries: []),
        ),
        messageKindClassifier: MessageKindClassifier.fromJson(
          File('assets/seed/message_cues_in.json').readAsStringSync(),
        ),
        supportingSmsClassifier: withSupporting
            ? SupportingSmsClassifier.fromJson(
                File(SupportingSmsClassifier.assetPath).readAsStringSync(),
              )
            : null,
        financialCalendar:
            const FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
      );

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    ingestor = build(withSupporting: true);
  });

  tearDown(() async {
    await database.close();
  });

  RawSms sms(String id, String body, DateTime at, {String sender = 'VK-BANK'}) {
    return RawSms(id: id, sender: sender, body: body, receivedAt: at);
  }

  Future<List<TransactionSmsMessage>> messages(String id) =>
      TransactionSmsRepository(database).messagesFor(id);

  final debitAt = DateTime.utc(2026, 11, 5, 5);
  const emiNotice =
      'Dear Customer, your loan EMI of Rs 12,345.00 is due on 05-Nov-26. '
      'Please maintain sufficient balance in A/c XX1234. -HDFC Bank';
  const emiDebit = 'INR 12,345.00 debited from A/c XX1234 towards your loan '
      'EMI on 05-Nov-26.';

  test('EMI notice before the debit: no transaction, then linked', () async {
    await ingestor.ingest(
      sms('sms_notice', emiNotice, debitAt.subtract(const Duration(days: 3))),
    );
    expect(await database.select(database.transactions).get(), isEmpty);

    await ingestor.ingest(sms('sms_debit', emiDebit, debitAt));

    final transaction =
        await database.select(database.transactions).getSingle();
    expect(transaction.id, 'txn_sms_debit');
    expect(transaction.amount, 12345.0);
    final shown = await messages(transaction.id);
    expect(shown.map((m) => m.smsId), ['sms_debit', 'sms_notice']);
    expect(shown.first.role, TransactionSmsRole.primary);
    expect(shown.last.role, TransactionSmsRole.supporting);
    expect(shown.last.kind, 'emi_notice');
  });

  test('EMI notice after the debit links when it arrives', () async {
    await ingestor.ingest(sms('sms_debit', emiDebit, debitAt));
    await ingestor.ingest(
      sms('sms_notice', emiNotice, debitAt.subtract(const Duration(days: 1))),
    );

    expect(await database.select(database.transactions).get(), hasLength(1));
    final shown = await messages('txn_sms_debit');
    expect(shown.map((m) => m.smsId), ['sms_debit', 'sms_notice']);
  });

  test('a settled RD debit still creates its transaction unchanged', () async {
    const body = 'Rs 5,000.00 debited from A/c XX1234 on 05-Nov-26 towards RD '
        'A/c 3300112233 instalment. -SBI';
    final plain = AppDatabase(NativeDatabase.memory());
    addTearDown(plain.close);
    final baseline = SmsIngestor(
      database: plain,
      parser: const ParserCascade(
        templateMatcher: TemplateMatcher(registries: []),
      ),
      messageKindClassifier: MessageKindClassifier.fromJson(
        File('assets/seed/message_cues_in.json').readAsStringSync(),
      ),
      financialCalendar:
          const FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );

    await baseline.ingest(sms('sms_rd', body, debitAt));
    await ingestor.ingest(sms('sms_rd', body, debitAt));

    final before = await plain.select(plain.transactions).get();
    final after = await database.select(database.transactions).get();
    expect(after, hasLength(1));
    expect(after.single.amount, before.single.amount);
    expect(after.single.ts, before.single.ts);
    expect(after.single.direction, before.single.direction);
    expect(after.single.lifecycleState, before.single.lifecycleState);
    expect(after.single.messageKind, before.single.messageKind);
    // The bank debit is its own primary SMS; it is never also "supporting".
    expect(await database.select(database.smsTransactionLinks).get(), isEmpty);
  });

  test('RD advice without a bank debit verb attaches to the debit', () async {
    await ingestor.ingest(
      sms(
        'sms_rd_debit',
        'INR 5,000.00 debited from A/c XX1234 via NACH on 05-Nov-26.',
        debitAt,
      ),
    );
    await ingestor.ingest(
      sms(
        'sms_rd_advice',
        'ICICI Bank: RD instalment of INR 5,000.00 processed for RD A/c '
            'XX9988, source A/c XX1234. Available balance INR 80,000.00.',
        debitAt.add(const Duration(hours: 1)),
      ),
    );

    expect(await database.select(database.transactions).get(), hasLength(1));
    final shown = await messages('txn_sms_rd_debit');
    expect(shown.map((m) => m.kind), [null, 'rd_instalment']);
  });

  test('collect request is understood, creates nothing, and links to payment',
      () async {
    await ingestor.ingest(
      sms(
        'sms_req',
        'Ravi Kumar has requested Rs 500.00 from you via UPI. Approve in '
            'your UPI app.',
        debitAt.subtract(const Duration(minutes: 30)),
      ),
    );
    expect(await database.select(database.transactions).get(), isEmpty);
    final raw = await database.select(database.rawSms).getSingle();
    expect(raw.processed, isTrue);
    expect(raw.failureReason, isNull);

    await ingestor.ingest(
      sms(
        'sms_paid',
        'INR 500.00 debited from A/c XX1234 via UPI to ravi@ybl. UPI Ref '
            '612345678901.',
        debitAt,
      ),
    );

    final shown = await messages('txn_sms_paid');
    expect(shown.map((m) => m.smsId), ['sms_paid', 'sms_req']);
    expect(shown.last.kind, 'collect_request');
  });

  test('without the supporting classifier unknown SMS stay unparsed', () async {
    final legacy = build(withSupporting: false);
    await legacy.ingest(
      sms(
        'sms_req',
        'Ravi Kumar has requested Rs 500.00 from you via UPI.',
        debitAt,
      ),
    );
    final raw = await database.select(database.rawSms).getSingle();
    expect(raw.processed, isFalse);
    expect(raw.failureReason, 'unparsed');
  });

  test('negative messages create no links and keep their old outcome',
      () async {
    await ingestor.ingest(
      sms('sms_debit', 'INR 500.00 debited from A/c XX1234 via UPI to a@ybl.',
          debitAt,),
    );
    await ingestor.ingest(
      sms(
        'sms_declined',
        'Collect request of Rs 500.00 from ravi@ybl was declined.',
        debitAt,
      ),
    );
    await ingestor.ingest(
      sms('sms_otp', '123456 is your OTP for payment request of Rs 500.',
          debitAt,),
    );
    await ingestor.ingest(
      sms('sms_promo', 'Get dividend-like returns! Invest Rs 500 now.',
          debitAt,),
    );
    expect(await database.select(database.smsTransactionLinks).get(), isEmpty);
  });
}
