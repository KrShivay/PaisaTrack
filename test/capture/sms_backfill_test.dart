import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

import '../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  RawSms message(String id) => RawSms(
        id: id,
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: DateTime.utc(2026, 5, 2, 9, 15),
      );

  SmsBackfiller backfiller({
    required List<RawSms> inbox,
    int chunkSize = 25,
  }) {
    final ingestor = SmsIngestor(
      database: database,
      parser: FakeParserCascade.ok(_sampleRecord),
    );
    return SmsBackfiller(
      ingestor: ingestor,
      reader: FakeInboxReader(inbox),
      chunkSize: chunkSize,
    );
  }

  test('backfills inbox history into raw_sms and transactions', () async {
    final processed = await backfiller(
      inbox: [message('sms_a'), message('sms_b')],
    ).run(now: DateTime(2026, 7, 5));

    expect(processed, 2);
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows.map((row) => row.id), containsAll(['sms_a', 'sms_b']));
    final transactions = await database.select(database.transactions).get();
    expect(
      transactions.map((row) => row.id),
      containsAll(['txn_sms_a', 'txn_sms_b']),
    );
  });

  test('re-running backfill inserts no duplicate rows (idempotent)', () async {
    final inbox = [message('sms_a'), message('sms_b')];

    await backfiller(inbox: inbox).run(now: DateTime(2026, 7, 5));
    await backfiller(inbox: inbox).run(now: DateTime(2026, 7, 5));

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(2));
    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(2));
  });

  test('dedups against a message already present in raw_sms', () async {
    // Simulate a message captured live before the backfill runs.
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_a',
            sender: 'VK-HDFCBK',
            body: 'Spent Rs 449',
            receivedAt: DateTime.utc(2026, 5, 2, 9, 15),
            purgeAfter: DateTime.utc(2026, 6, 1),
          ),
        );

    await backfiller(inbox: [message('sms_a')]).run(now: DateTime(2026, 7, 5));

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));
    expect(rawRows.single.id, 'sms_a');
  });

  test('processes across chunk boundaries', () async {
    final inbox = List.generate(7, (i) => message('sms_$i'));

    final processed = await backfiller(
      inbox: inbox,
      chunkSize: 3,
    ).run(now: DateTime(2026, 7, 5));

    expect(processed, 7);
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(7));
  });

  test('provider runs backfill once and marks it complete', () async {
    final marker = FakeBackfillMarker();
    final container = _backfillContainer(
      database: database,
      inbox: [message('sms_a')],
      marker: marker,
    );
    addTearDown(container.dispose);
    await container.read(smsPermissionControllerProvider.future);
    await container.read(appDatabaseProvider.future);

    final processed = await container.read(smsBackfillProvider.future);

    expect(processed, 1);
    expect(marker.complete, isTrue);
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));
  });

  test('provider skips backfill when the marker is already complete', () async {
    final marker = FakeBackfillMarker()..complete = true;
    final reader = FakeInboxReader([message('sms_a')]);
    final container = _backfillContainer(
      database: database,
      reader: reader,
      marker: marker,
    );
    addTearDown(container.dispose);
    await container.read(smsPermissionControllerProvider.future);
    await container.read(appDatabaseProvider.future);

    final processed = await container.read(smsBackfillProvider.future);

    expect(processed, 0);
    expect(reader.readCount, 0);
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, isEmpty);
  });
}

ProviderContainer _backfillContainer({
  required AppDatabase database,
  required FakeBackfillMarker marker,
  List<RawSms> inbox = const [],
  FakeInboxReader? reader,
}) {
  return ProviderContainer(
    overrides: [
      smsPermissionGateProvider.overrideWithValue(
        FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
      ),
      appDatabaseProvider.overrideWith((ref) async => database),
      smsInboxReaderProvider
          .overrideWithValue(reader ?? FakeInboxReader(inbox)),
      parserCascadeProvider.overrideWith(
        (ref) async => FakeParserCascade.ok(_sampleRecord),
      ),
      backfillMarkerProvider.overrideWithValue(marker),
    ],
  );
}

final _sampleRecord = NormalizedTransactionRecord(
  amount: 449,
  direction: TransactionDirection.debit,
  channel: TransactionChannel.upi,
  merchantRaw: 'AMZN*MKTPLC',
  counterpartyVpa: null,
  accountHint: 'xx4521',
  balanceAfter: 12384.5,
  refId: '615223847712',
  ts: DateTime.utc(2026, 5, 2, 9, 15),
  parseSource: ParseSource.template,
  parseConfidence: 0.97,
);

class FakeInboxReader implements SmsInboxReader {
  FakeInboxReader(this._messages);

  final List<RawSms> _messages;
  int readCount = 0;

  @override
  Future<List<RawSms>> readSince(DateTime since) async {
    readCount++;
    return _messages;
  }
}

class FakeBackfillMarker implements BackfillMarker {
  bool complete = false;

  @override
  Future<bool> isComplete() async => complete;

  @override
  Future<void> markComplete() async {
    complete = true;
  }
}

class FakeParserCascade extends ParserCascade {
  FakeParserCascade.ok(this._record)
      : super(templateMatcher: const TemplateMatcher(registries: []));

  final NormalizedTransactionRecord _record;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    return Ok(_record);
  }
}
