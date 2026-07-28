import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/generic_transaction_parser.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';

void main() {
  late AppDatabase database;
  late MessageKindClassifier classifier;
  late SmsIngestor ingestor;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final cueFile = File('assets/seed/message_cues_in.json');
    classifier = MessageKindClassifier.fromJson(cueFile.readAsStringSync());
    const parser = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
      genericTransactionParser: GenericTransactionParser(),
    );
    ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: classifier,
      now: () => DateTime.utc(2026, 7, 10),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('failed and reversed transactions persist in DB with lifecycle_state and are excluded from spending totals', () async {
    // 1. Settled transaction
    await ingestor.ingest(
      RawSms(
        id: 'sms_settled_1',
        sender: 'VK-HDFCBK',
        body: 'INR 1000 debited from A/C XX1234 for Swiggy',
        receivedAt: DateTime.utc(2026, 7, 5),
      ),
    );

    // 2. Failed transaction (narrowed _hardReject now parses amount and direction)
    await ingestor.ingest(
      RawSms(
        id: 'sms_failed_1',
        sender: 'JX-AXISBK',
        body: 'Transaction of INR 500 on Axis Bank Credit Card XX5678 has been declined due to security reasons',
        receivedAt: DateTime.utc(2026, 7, 6),
      ),
    );

    // 3. Reversed transaction
    await ingestor.ingest(
      RawSms(
        id: 'sms_reversed_1',
        sender: 'VK-HDFCBK',
        body: 'Reversal of INR 300 credited back to A/C XX1234',
        receivedAt: DateTime.utc(2026, 7, 7),
      ),
    );

    // 4. Reminder (routed away, never stored in transactions table)
    await ingestor.ingest(
      RawSms(
        id: 'sms_reminder_1',
        sender: 'JX-AXISBK-S',
        body: 'Payment of INR 2086 for your Axis Bank Credit Card no. XX5678 is due on 30-12-25',
        receivedAt: DateTime.utc(2026, 7, 8),
      ),
    );

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(3));

    final failedTxn = transactions.firstWhere((t) => t.smsId == 'sms_failed_1');
    expect(failedTxn.lifecycleState, 'failed');
    expect(failedTxn.lifecycleReason, 'declined');
    expect(failedTxn.messageKind, 'failed');

    final reversedTxn = transactions.firstWhere((t) => t.smsId == 'sms_reversed_1');
    expect(reversedTxn.lifecycleState, 'reversed');
    expect(reversedTxn.lifecycleReason, 'refund_or_reversal');
    expect(reversedTxn.messageKind, 'reversal');

    final settledTxn = transactions.firstWhere((t) => t.smsId == 'sms_settled_1');
    expect(settledTxn.lifecycleState, 'settled');

    // Dashboard spending totals should only include settled rows
    final dashboardRepo = DashboardRepository(database);
    final snapshot = await dashboardRepo.load(
      DashboardQueryWindow(
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 7, 31),
        trendStart: DateTime.utc(2026, 7, 1),
        trendEnd: DateTime.utc(2026, 7, 31),
        previousStart: DateTime.utc(2026, 6, 1),
        previousEnd: DateTime.utc(2026, 6, 30),
      ),
    );

    // Only 1000 from settled transaction should enter debit total (500 failed row is excluded)
    expect(snapshot.debitTotal, 1000.0);
  });
}
