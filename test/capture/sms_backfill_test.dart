import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/capture_decision_provenance.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/parser_version.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/capture/sms_import_state.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/enrichment/decision_policy.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

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

  RawSms syntheticMessage(String id, String body) => RawSms(
        id: id,
        sender: 'VK-HDFCBK',
        body: body,
        receivedAt: DateTime.utc(2026, 5, 2, 9, 15),
      );

  SmsBackfiller backfiller(
    SmsInboxReader reader, {
    Set<String> throwIds = const {},
    Set<String> unparsedIds = const {},
  }) {
    return SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(
          _sampleRecord,
          throwIds: throwIds,
          unparsedIds: unparsedIds,
        ),
        messageKindClassifier: _testMessageKindClassifier,
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
    expect(result.transactionsFound, 2);
    expect(result.alreadyKnown, 0);
    expect(reader.requestedCursors, [null, cursor]);
    final transactions = await database.select(database.transactions).get();
    expect(
      transactions.map((row) => row.id),
      containsAll(['txn_sms_current', 'txn_sms_2022']),
    );
  });

  test('live, history, and catch-up resolve decorated payee identity equally',
      () async {
    final resolver = MerchantResolver(database, const NoopEmbedder());
    final record = NormalizedTransactionRecord(
      amount: 449,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'UPI-SWIGGY',
      counterpartyVpa: 'swiggy@ybl',
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 5, 2, 9, 15),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );
    final live = SmsIngestor(
      database: database,
      parser: FakeParserCascade(record),
      messageKindClassifier: _testMessageKindClassifier,
      merchantResolver: resolver,
    );
    await live.ingest(message('sms_identity_live'));

    final history = SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(record),
        messageKindClassifier: _testMessageKindClassifier,
        merchantResolver: resolver,
      ),
      reader: FakeInboxReader.single([message('sms_identity_history')]),
    );
    await history.run();

    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(record),
        messageKindClassifier: _testMessageKindClassifier,
        merchantResolver: resolver,
      ),
      reader: FakeInboxReader.single([message('sms_identity_catchup')]),
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );
    await catchUp.run();

    final rows = await (database.select(database.transactions)
          ..where(
            (row) => row.smsId.isIn([
              'sms_identity_live',
              'sms_identity_history',
              'sms_identity_catchup',
            ]),
          ))
        .get();
    expect(rows, hasLength(3));
    expect(
      rows.map((row) => row.merchantId),
      everyElement('merchant_SWIGGY'),
    );
  });

  test(
      'merchant_id rule applies to resolved text-only payee in every capture path',
      () async {
    final resolver = MerchantResolver(database, const NoopEmbedder());
    final seedRecord = NormalizedTransactionRecord(
      amount: 449,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'UPI-SWIGGY',
      counterpartyVpa: 'swiggy@ybl',
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 5, 2, 9, 15),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );
    final categorizer = Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap(const {}),
    );
    final seeded = SmsIngestor(
      database: database,
      parser: FakeParserCascade(seedRecord),
      messageKindClassifier: _testMessageKindClassifier,
      merchantResolver: resolver,
      categorizer: categorizer,
    );
    await seeded.ingest(message('sms_resolved_rule_seed'));
    await TransactionRepository(database).correctWithRule(
      txnId: 'txn_sms_resolved_rule_seed',
      categoryId: 'food_dining',
      context: 'ask_now',
    );

    final textOnlyRecord = NormalizedTransactionRecord(
      amount: 125,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'SWIGGY',
      counterpartyVpa: null,
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 5, 3, 9, 15),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );
    SmsIngestor ingestor(String _) => SmsIngestor(
          database: database,
          parser: FakeParserCascade(textOnlyRecord),
          messageKindClassifier: _testMessageKindClassifier,
          merchantResolver: resolver,
          categorizer: categorizer,
        );

    await ingestor('live').ingest(
      syntheticMessage('sms_resolved_rule_live', 'Spent Rs 125'),
    );
    await SmsBackfiller(
      ingestor: ingestor('history'),
      reader: FakeInboxReader.single([
        syntheticMessage('sms_resolved_rule_history', 'Spent Rs 125'),
      ]),
    ).run();
    await SmsIncrementalCatchUp(
      database: database,
      ingestor: ingestor('catchup'),
      reader: FakeInboxReader.single([
        syntheticMessage('sms_resolved_rule_catchup', 'Spent Rs 125'),
      ]),
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    ).run();

    final rows = await (database.select(database.transactions)
          ..where(
            (row) => row.smsId.isIn([
              'sms_resolved_rule_live',
              'sms_resolved_rule_history',
              'sms_resolved_rule_catchup',
            ]),
          ))
        .get();
    expect(rows, hasLength(3));
    expect(rows.map((row) => row.merchantId), everyElement('merchant_SWIGGY'));
    expect(rows.map((row) => row.categoryId), everyElement('food_dining'));
  });

  test(
      'bounded history generic-only import reviews supported payment and abstains on failed or future wording',
      () async {
    final messages = [
      syntheticMessage(
        'sms_history_charge',
        'Your card XX1234 was charged Rs. 725.00 at SANITIZED STORE',
      ),
      syntheticMessage(
        'sms_history_failed',
        'A/c XX1234 failed for Rs. 500.00 via UPI',
      ),
      syntheticMessage(
        'sms_history_reversal',
        'Reversal of INR 300.00 credited back to A/c XX1234',
      ),
      syntheticMessage(
        'sms_history_pending',
        'UPI payment of Rs. 500 is pending from A/c XX1234',
      ),
    ];
    final importer = SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: const ParserCascade(
          templateMatcher: TemplateMatcher(registries: []),
        ),
        messageKindClassifier: _testMessageKindClassifier,
      ),
      reader: FakeInboxReader.single(messages),
      pageSize: 2,
    );

    final result = await importer.run();

    expect(result.processed, messages.length);
    expect(result.parsed, 1);
    expect(result.unparsed, 3);
    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_sms_history_charge');
    expect(transactions.single.status, 'needs_review');
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(messages.length));
    expect(
      rawRows.where((row) => row.id != 'sms_history_charge').every(
            (row) =>
                !row.processed &&
                row.failureReason == SmsFailureReason.unparsed,
          ),
      isTrue,
    );
  });

  test('history rule hit clamps asked to review with fixed-review provenance',
      () async {
    await RuleRepository(database).insert(
      matchType: 'merchant',
      matchValue: 'swiggy',
      setCategoryId: 'groceries',
    );
    final record = NormalizedTransactionRecord(
      amount: 449,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'SWIGGY',
      counterpartyVpa: 'first-time@upi',
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 5, 2, 9, 15),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );
    final result = await SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(record),
        categorizer: Categorizer(
          rules: RuleRepository(database),
          seedMap: SeedCategoryMap(const {}),
        ),
        fixedStatus: DecisionStatus.needsReview,
        captureDecisionStatusMode: CaptureDecisionStatusMode.fixedReview,
        messageKindClassifier: _testMessageKindClassifier,
      ),
      reader: FakeInboxReader.single([message('sms_rule_history')]),
    ).run();

    expect(result.parsed, 1);
    final transaction = await (database.select(database.transactions)
          ..where((row) => row.smsId.equals('sms_rule_history')))
        .getSingle();
    expect(transaction.categoryId, 'groceries');
    expect(transaction.status, 'needs_review');
    final confidence =
        jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
    final decision = confidence['capture_decision']! as Map<String, Object?>;
    expect(decision['status_mode'], 'fixed_review');
    expect(decision['category_source'], 'rule');
  });

  test('resume rule hit clamps asked to review with fixed-review provenance',
      () async {
    await RuleRepository(database).insert(
      matchType: 'merchant_legacy',
      matchValue: 'amzn',
      setCategoryId: 'groceries',
    );
    final record = NormalizedTransactionRecord(
      amount: 449,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: 'AMZN*MKTPLC',
      counterpartyVpa: 'first-time@upi',
      accountHint: null,
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2026, 5, 2, 9, 15),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
    );
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(record),
        categorizer: Categorizer(
          rules: RuleRepository(database),
          seedMap: SeedCategoryMap(const {}),
        ),
        fixedStatus: DecisionStatus.needsReview,
        captureDecisionStatusMode: CaptureDecisionStatusMode.fixedReview,
        messageKindClassifier: _testMessageKindClassifier,
      ),
      reader: FakeInboxReader.single([message('sms_rule_resume')]),
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );

    await catchUp.run();

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.smsId.equals('sms_rule_resume')))
        .getSingle();
    expect(transaction.categoryId, 'groceries');
    expect(transaction.status, 'needs_review');
    final confidence =
        jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
    final decision = confidence['capture_decision']! as Map<String, Object?>;
    expect(decision['status_mode'], 'fixed_review');
    expect(decision['category_source'], 'rule');
  });

  test('fixed-review history import skips merchant embeddings', () async {
    final embedder = _CountingEmbedder();
    final record = _sampleRecord;
    final result = await SmsBackfiller(
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(record),
        categorizer: Categorizer(
          rules: RuleRepository(database),
          seedMap: SeedCategoryMap(const {}),
        ),
        merchantResolver: MerchantResolver(database, embedder),
        fixedStatus: DecisionStatus.needsReview,
        captureDecisionStatusMode: CaptureDecisionStatusMode.fixedReview,
        messageKindClassifier: _testMessageKindClassifier,
      ),
      reader: FakeInboxReader.single([message('sms_fixed_review_no_embed')]),
    ).run();

    expect(result.parsed, 1);
    expect(embedder.calls, 0);
  });

  test('aggregates privacy-safe outcome counts across pages', () async {
    final reader = FakeInboxReader([
      SmsInboxPage(
        messages: [message('sms_parsed')],
        scanned: 3,
        filterRejected: 1,
        unknownSender: 1,
        accepted: 1,
        nextCursor: const SmsInboxCursor(beforeEpochMillis: 900, beforeId: 9),
      ),
      SmsInboxPage(
        messages: [message('sms_unparsed')],
        scanned: 2,
        filterRejected: 1,
        accepted: 1,
      ),
    ]);

    final result = await backfiller(
      reader,
      unparsedIds: {'sms_unparsed'},
    ).run();

    expect(result.scanned, 5);
    expect(result.filterRejected, 2);
    expect(result.unknownSender, 1);
    expect(result.accepted, 2);
    expect(result.parsed, 1);
    expect(result.unparsed, 1);
    expect(result.transactionsFound, 1);
    expect(result.alreadyKnown, 0);
  });

  test('decodes native inbox outcome counts without raw-content fields',
      () async {
    const channel = MethodChannel('com.paisatrack/sms_backfill_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'messages': [
          <String, Object?>{
            'id': 'sms_native',
            'sender': 'VK-HDFCBK',
            'body': 'Spent Rs 449',
            'receivedAtEpochMillis': 1777713300000,
          },
        ],
        'hasMore': false,
        'scanned': 4,
        'filterRejected': 2,
        'unknownSender': 1,
        'accepted': 1,
      };
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final page = await const PlatformSmsInboxReader(channel: channel).readPage(
      limit: 10,
    );

    expect(page.scanned, 4);
    expect(page.filterRejected, 2);
    expect(page.unknownSender, 1);
    expect(page.accepted, 1);
    expect(page.messages.single.id, 'sms_native');
  });

  test('reports new and already-known transactions separately', () async {
    final first = await backfiller(
      FakeInboxReader.single([message('sms_known')]),
    ).run();
    final second = await backfiller(
      FakeInboxReader.single([message('sms_known')]),
    ).run();

    expect(first.transactionsFound, 1);
    expect(first.alreadyKnown, 0);
    expect(second.transactionsFound, 0);
    expect(second.alreadyKnown, 1);
  });

  test('SmsBackfillStatusNotifier updates progress state and stage', () {
    final notifier = SmsBackfillStatusNotifier();
    expect(notifier.state.stage, SmsBackfillStage.idle);

    notifier.updateProgress(processed: 100, failed: 2);
    expect(notifier.state.stage, SmsBackfillStage.running);
    expect(notifier.state.processed, 100);
    expect(notifier.state.failed, 2);

    notifier.markCompleted(processed: 100, failed: 2);
    expect(notifier.state.stage, SmsBackfillStage.completed);
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

  test('production catch-up provider uses lifecycle cues without an LLM',
      () async {
    final expected = jsonDecode(
      File('test/fixtures/sms/sbi/sbi_debit_dearupi_01.expected.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final fixtureBody = File(
      'test/fixtures/sms/sbi/sbi_debit_dearupi_01.txt',
    ).readAsStringSync();
    final receivedAt = DateTime.fromMillisecondsSinceEpoch(
      expected['received_at']! as int,
      isUtc: true,
    );
    final reader = FakeInboxReader.single([
      RawSms(
        id: 'sms_provider_fixture',
        sender: expected['sender']! as String,
        body: fixtureBody,
        receivedAt: receivedAt,
      ),
      syntheticMessage(
        'sms_provider_balance',
        'Available balance INR 500.00. Monthly view shows Rs 100 spent.',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        smsInboxReaderProvider.overrideWithValue(reader),
        embedderProvider.overrideWithValue(const NoopEmbedder()),
        financialCalendarProvider.overrideWithValue(
          const FinancialCalendar.fixed(Duration.zero),
        ),
        backfillMarkerProvider.overrideWithValue(
          FakeBackfillMarker(version: smsHistoryImportVersion),
        ),
      ],
    );
    addTearDown(container.dispose);

    final catchUp = await container.read(smsIncrementalCatchUpProvider.future);
    final result = await catchUp.run();

    expect(result.processed, 2);
    final transactions = await database.select(database.transactions).get();
    expect(
      transactions,
      hasLength(1),
      reason: 'unexpected synthetic transaction SMS IDs: '
          '${transactions.map((row) => row.smsId).toList()}',
    );
    expect(transactions.single.smsId, 'sms_provider_fixture');
    expect(
      transactions.single.ts,
      DateTime.utc(2023, 11, 7).millisecondsSinceEpoch,
    );
    expect(transactions.single.lifecycleState, 'settled');
    expect(transactions.single.merchantId, 'merchant_JANEDOE');
    final rawRows = await database.select(database.rawSms).get();
    final balanceRaw = rawRows.singleWhere(
      (row) => row.id == 'sms_provider_balance',
    );
    expect(balanceRaw.processed, isTrue);
    expect(balanceRaw.failureReason, isNull);
  });

  test('production history provider uses lifecycle cues without an LLM',
      () async {
    final reader = FakeInboxReader.single([
      RawSms(
        id: 'sms_history_fixture',
        sender: 'VK-SBIUPI',
        body: File('test/fixtures/sms/sbi/sbi_debit_dearupi_01.txt')
            .readAsStringSync(),
        receivedAt: DateTime.utc(2026, 7, 6, 15, 51),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        smsInboxReaderProvider.overrideWithValue(reader),
        embedderProvider.overrideWithValue(const NoopEmbedder()),
        financialCalendarProvider.overrideWithValue(
          const FinancialCalendar.fixed(Duration.zero),
        ),
        backfillMarkerProvider.overrideWithValue(FakeBackfillMarker()),
      ],
    );
    addTearDown(container.dispose);

    final importer =
        await container.read(smsHistoryImportRunnerProvider.future);
    final result = await importer.run(force: true);

    expect(result.processed, 1);
    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.smsId, 'sms_history_fixture');
    expect(transactions.single.merchantId, 'merchant_JANEDOE');
    expect(
      transactions.single.ts,
      DateTime.utc(2023, 11, 7).millisecondsSinceEpoch,
    );
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
        messageKindClassifier: _testMessageKindClassifier,
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

  test('incremental catch-up retries retained failures after parser upgrade',
      () async {
    await SmsIngestor(
      database: database,
      parser: FakeParserCascade(
        _sampleRecord,
        unparsedIds: {'sms_failed'},
      ),
      messageKindClassifier: _testMessageKindClassifier,
    ).ingest(message('sms_failed'));

    final reader = FakeInboxReader.single([message('sms_failed')]);
    final catchUp = SmsIncrementalCatchUp(
      database: database,
      ingestor: SmsIngestor(
        database: database,
        parser: FakeParserCascade(_sampleRecord),
        messageKindClassifier: _testMessageKindClassifier,
        parserVersion: smsParserVersion + 1,
      ),
      reader: reader,
      marker: FakeBackfillMarker(version: smsHistoryImportVersion),
    );

    final result = await catchUp.run();

    expect(result.processed, 1);
    expect(result.failed, 0);
    expect(await database.select(database.transactions).get(), hasLength(1));
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
        messageKindClassifier: _testMessageKindClassifier,
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
        messageKindClassifier: _testMessageKindClassifier,
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
        messageKindClassifier: _testMessageKindClassifier,
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
        messageKindClassifier: _testMessageKindClassifier,
      ),
      reader: reader,
      marker: FakeBackfillMarker(version: smsHistoryImportVersion - 1),
    );

    final result = await catchUp.run();

    expect(result.skipped, isTrue);
    expect(reader.readCount, 0);
  });
}

class _CountingEmbedder implements Embedder {
  int calls = 0;

  @override
  Future<Float32List?> embed(String text) async {
    calls++;
    return null;
  }

  @override
  Future<bool> isModelAvailable() async => true;

  @override
  Future<bool> downloadModel() async => true;

  @override
  Future<bool> deleteModel() async => true;
}

final _testMessageKindClassifier = MessageKindClassifier.fromJson(
  File('assets/seed/message_cues_in.json').readAsStringSync(),
);

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
  FakeParserCascade(
    this._record, {
    this.throwIds = const {},
    this.unparsedIds = const {},
  }) : super(templateMatcher: const TemplateMatcher(registries: []));

  final NormalizedTransactionRecord _record;
  final Set<String> throwIds;
  final Set<String> unparsedIds;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms, {
    FinancialCalendar? calendar,
  }) async {
    if (throwIds.contains(sms.id)) throw StateError('simulated parse failure');
    if (unparsedIds.contains(sms.id)) {
      return const Err(ParseFailure.unparsed);
    }
    var resRecord = _record;
    if (resRecord.evidence == null || resRecord.evidence!.isEmpty) {
      final amountStr = resRecord.amount == resRecord.amount.toInt()
          ? resRecord.amount.toInt().toString()
          : resRecord.amount.toString();
      final idx = sms.body.indexOf(amountStr);
      final start = idx >= 0 ? idx : 0;
      final end = idx >= 0 ? idx + amountStr.length : sms.body.length;
      resRecord = resRecord.withEvidence([
        FieldEvidence(
          field: 'amount',
          start: start,
          end: end,
          verbatim: sms.body.substring(start, end),
          extractor: 'test',
        ),
        FieldEvidence(
          field: 'direction',
          start: 0,
          end: sms.body.length,
          verbatim: sms.body,
          extractor: 'test',
        ),
        FieldEvidence(
          field: 'ts',
          start: 0,
          end: sms.body.length,
          verbatim: sms.body,
          extractor: 'test',
        ),
      ]);
    }
    return Ok(resRecord);
  }
}
