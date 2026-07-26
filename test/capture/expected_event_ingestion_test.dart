import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
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
    final classifier = MessageKindClassifier(
      cues: {
        MessageKind.reminder: [RegExp(r'reminder', caseSensitive: false)],
        MessageKind.mandate: [RegExp(r'mandate|autopay', caseSensitive: false)],
      },
    );
    ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: classifier,
      expectedEventRepository: repository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('Three reminders for the same bill produce exactly 1 expected event and 0 transactions', () async {
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
      body: 'Reminder 2: Your credit card bill of Rs 4500 is due on 15-Jul-2026.',
      receivedAt: now,
    );
    final sms3 = RawSms(
      id: 'sms_rem_3',
      sender: 'HDFCBK',
      body: 'Final Reminder: Your credit card bill of Rs 4500 is due on 15-Jul-2026.',
      receivedAt: now,
    );

    await ingestor.ingest(sms1);
    await ingestor.ingest(sms2);
    await ingestor.ingest(sms3);

    // AC: 3 reminders produce 1 expected event
    final events = await repository.getExpectedEvents();
    expect(events, hasLength(1));
    expect(events.first.expectedAmountPaise, 450000);
    expect(events.first.label, contains('HDFCBK'));

    // AC: A reminder NEVER creates a transaction
    final txns = await database.select(database.transactions).get();
    expect(txns, isEmpty);
  });
}
