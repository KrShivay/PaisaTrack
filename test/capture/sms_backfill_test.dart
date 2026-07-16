import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/capture/sms_import_state.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
  });

  RawSms message(String id, {int year = 2026}) => RawSms(
        id: id,
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: DateTime.utc(year, 5, 2, 9, 15),
      );

  SmsBackfiller backfiller(
    SmsInboxReader reader, {
    Set<String> throwIds = const {},
  }) {
    return SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord, throwIds: throwIds),
      ),
      reader: reader,
      pageSize: 2,
    );
  }

  test('imports every page including transactions older than three months',
      () async {
    const cursor = SmsInboxCursor(beforeEpochMillis: 1000, beforeId: 10);
    final reader = FakeInboxReader([
      SmsInboxPage(
        messages: [message('sms_current')],
        nextCursor: cursor,
      ),
      SmsInboxPage(messages: [message('sms_2022', year: 2022)]),
    ]);

    final result = await backfiller(reader).run();

    expect(result.processed, 2);
    expect(result.failed, 0);
    expect(reader.requestedCursors, [null, cursor]);
    final transactions = await database.select(database.transactions).get();
    expect(
      transactions.map((row) => row.id),
      containsAll(['txn_sms_current', 'txn_sms_2022']),
    );
  });

  test('continues after a page containing no filter-approved messages',
      () async {
    const cursor = SmsInboxCursor(beforeEpochMillis: 900, beforeId: 9);
    final reader = FakeInboxReader([
      const SmsInboxPage(messages: [], nextCursor: cursor),
      SmsInboxPage(messages: [message('sms_old', year: 2020)]),
    ]);

    final result = await backfiller(reader).run();

    expect(result.processed, 1);
    expect(reader.requestedCursors, [null, cursor]);
  });

  test('rejects a non-advancing inbox cursor', () async {
    const cursor = SmsInboxCursor(beforeEpochMillis: 900, beforeId: 9);
    final reader = FakeInboxReader(const [
      SmsInboxPage(messages: [], nextCursor: cursor),
      SmsInboxPage(messages: [], nextCursor: cursor),
    ]);

    await expectLater(
      backfiller(reader).run(),
      throwsA(isA<StateError>()),
    );
  });

  test('re-import is idempotent', () async {
    final inbox = [message('sms_a'), message('sms_b')];

    await backfiller(FakeInboxReader.single(inbox)).run();
    await backfiller(FakeInboxReader.single(inbox)).run();

    expect(await database.select(database.rawSms).get(), hasLength(2));
    expect(await database.select(database.transactions).get(), hasLength(2));
  });

  test('one imported page emits one transaction-table change', () async {
    final emissions = <List<Transaction>>[];
    final subscription =
        database.select(database.transactions).watch().listen(emissions.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await backfiller(
      FakeInboxReader.single([message('sms_a'), message('sms_b')]),
    ).run();
    await pumpEventQueue();

    expect(emissions.where((rows) => rows.isNotEmpty), hasLength(1));
    expect(emissions.last, hasLength(2));
  });

  test('version 1 marker automatically catches up to full-history version',
      () async {
    final marker = FakeBackfillMarker(version: 1);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(
        FakeInboxReader.single([message('sms_pre_2023', year: 2022)]),
      ),
      marker: marker,
    );

    final result = await importer.run();

    expect(result.skipped, isFalse);
    expect(result.processed, 1);
    expect(marker.version, smsHistoryImportVersion);
    expect(marker.markCount, 1);
  });

  test('current import version skips automatic scan', () async {
    final marker = FakeBackfillMarker(version: smsHistoryImportVersion);
    final reader = FakeInboxReader.single([message('sms_a')]);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(reader),
      marker: marker,
    );

    final result = await importer.run();

    expect(result.skipped, isTrue);
    expect(reader.readCount, 0);
  });

  test('forced re-import bypasses current version marker', () async {
    final marker = FakeBackfillMarker(version: smsHistoryImportVersion);
    final reader = FakeInboxReader.single([message('sms_a')]);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(reader),
      marker: marker,
    );

    final result = await importer.run(force: true);

    expect(result.processed, 1);
    expect(reader.readCount, 1);
    expect(marker.markCount, 1);
  });

  test('automatic import resumes from the last completed page', () async {
    const checkpoint = SmsImportCheckpoint(
      beforeEpochMillis: 800,
      beforeId: 8,
    );
    final marker = FakeBackfillMarker(version: 1, checkpoint: checkpoint);
    final reader = FakeInboxReader.single([message('sms_old', year: 2021)]);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(reader),
      marker: marker,
    );

    final result = await importer.run();

    expect(result.processed, 1);
    expect(
      reader.requestedCursors,
      const [SmsInboxCursor(beforeEpochMillis: 800, beforeId: 8)],
    );
    expect(marker.checkpointValue, isNull);
  });

  test('automatic import saves its cursor after every completed page',
      () async {
    const next = SmsInboxCursor(beforeEpochMillis: 700, beforeId: 7);
    final marker = FakeBackfillMarker(version: 1);
    final reader = FakeInboxReader([
      const SmsInboxPage(messages: [], nextCursor: next),
      SmsInboxPage(messages: [message('sms_old', year: 2020)]),
    ]);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(reader),
      marker: marker,
    );

    await importer.run();

    expect(marker.savedCheckpoints, hasLength(1));
    expect(marker.savedCheckpoints.single.beforeEpochMillis, 700);
    expect(marker.savedCheckpoints.single.beforeId, 7);
    expect(marker.checkpointValue, isNull);
  });

  test('partial row failure completes scan and remains manually retryable',
      () async {
    final marker = FakeBackfillMarker(version: 1);
    final importer = SmsHistoryImporter(
      backfiller: backfiller(
        FakeInboxReader.single([message('sms_ok'), message('sms_bad')]),
        throwIds: {'sms_bad'},
      ),
      marker: marker,
    );

    final result = await importer.run();

    expect(result.processed, 2);
    expect(result.failed, 1);
    expect(marker.version, smsHistoryImportVersion);
    expect(marker.markCount, 1);
  });

  test('incremental catch-up recovers a recent gap behind a known SMS',
      () async {
    await backfiller(FakeInboxReader.single([message('sms_known')])).run();
    const next = SmsInboxCursor(beforeEpochMillis: 700, beforeId: 7);
    const older = SmsInboxCursor(beforeEpochMillis: 600, beforeId: 6);
    final reader = FakeInboxReader([
      SmsInboxPage(
        messages: [message('sms_new'), message('sms_known')],
        nextCursor: next,
      ),
      SmsInboxPage(
        messages: [message('sms_gap', year: 2025)],
        nextCursor: older,
      ),
      SmsInboxPage(messages: [message('sms_outside_overlap', year: 2024)]),
    ]);
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
      ),
      reader: reader,
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
      pageSize: 3,
    );

    final result = await catchUp.run();

    expect(result.processed, 2);
    expect(reader.readCount, 2);
    final transactionIds = (await database.select(database.transactions).get())
        .map((row) => row.id);
    expect(
      transactionIds,
      containsAll(['txn_sms_known', 'txn_sms_new', 'txn_sms_gap']),
    );
    expect(transactionIds, isNot(contains('txn_sms_outside_overlap')));
  });

  test('incremental catch-up queries only IDs in the current inbox page',
      () async {
    for (var index = 0; index < 500; index++) {
      await backfiller(
        FakeInboxReader.single([message('historical_$index')]),
      ).run();
    }
    final reader = FakeInboxReader.single([
      message('sms_new'),
      message('historical_499'),
    ]);
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
      ),
      reader: reader,
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );

    final result = await catchUp.run();

    expect(result.processed, 1);
    expect(reader.readCount, 1);
  });

  test('incremental catch-up succeeds on an empty inbox', () async {
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
      ),
      reader: FakeInboxReader.single([]),
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );

    final result = await catchUp.run();

    expect(result.processed, 0);
    expect(result.failed, 0);
  });

  test('incremental catch-up succeeds on a single-page inbox', () async {
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
      ),
      reader: FakeInboxReader.single([message('sms_single')]),
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );

    final result = await catchUp.run();

    expect(result.processed, 1);
    expect(
      (await database.select(database.transactions).get()).single.id,
      'txn_sms_single',
    );
  });

  test('incremental catch-up waits for the initial versioned import', () async {
    final reader = FakeInboxReader.single([message('sms_new')]);
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
      ),
      reader: reader,
      marker: FakeBackfillMarker(version: smsHistoryImportVersion - 1),
    );

    final result = await catchUp.run();

    expect(result.skipped, isTrue);
    expect(reader.readCount, 0);
  });
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
  FakeInboxReader(this._pages);

  factory FakeInboxReader.single(List<RawSms> messages) {
    return FakeInboxReader([SmsInboxPage(messages: messages)]);
  }

  final List<SmsInboxPage> _pages;
  final List<SmsInboxCursor?> requestedCursors = [];
  int readCount = 0;

  @override
  Future<SmsInboxPage> readPage({
    SmsInboxCursor? before,
    required int limit,
  }) async {
    requestedCursors.add(before);
    return _pages[readCount++];
  }
}

class FakeBackfillMarker implements BackfillMarker {
  FakeBackfillMarker({
    this.version = 0,
    SmsImportCheckpoint? checkpoint,
  }) : checkpointValue = checkpoint;

  int version;
  SmsImportCheckpoint? checkpointValue;
  final List<SmsImportCheckpoint> savedCheckpoints = [];
  int markCount = 0;
  int resetCount = 0;

  @override
  Future<SmsImportCheckpoint?> checkpoint() async => checkpointValue;

  @override
  Future<int> completedVersion() async => version;

  @override
  Future<void> markCompleted(int version) async {
    this.version = version;
    checkpointValue = null;
    markCount++;
  }

  @override
  Future<void> saveCheckpoint(SmsImportCheckpoint checkpoint) async {
    checkpointValue = checkpoint;
    savedCheckpoints.add(checkpoint);
  }

  @override
  Future<void> reset() async {
    version = 0;
    checkpointValue = null;
    resetCount++;
  }
}

class FakeParserCascade extends ParserCascade {
  FakeParserCascade(this._record, {this.throwIds = const {}})
      : super(templateMatcher: const TemplateMatcher(registries: []));

  final NormalizedTransactionRecord _record;
  final Set<String> throwIds;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    if (throwIds.contains(sms.id)) throw StateError('simulated parse failure');
    return Ok(_record);
  }
}
