import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/parser_version.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/field_normalizer.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/data/repositories/sms_disposition_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

import '../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    // The categorizer stamps category_id and foreign keys are enforced, so
    // ingest tests need the bundled category rows just like production.
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
  });

  test('decodes one optional exact legacy identity and old payloads', () {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    final oldPayload = decodeRawSmsPayload({
      'id': 'canonical-id',
      'sender': 'VK-HDFCBK',
      'body': 'Spent Rs 100',
      'receivedAtEpochMillis': receivedAt.millisecondsSinceEpoch,
    });
    expect(oldPayload.legacyId, isNull);
    expect(oldPayload.identityIds, {'canonical-id'});

    final compatiblePayload = decodeRawSmsPayload({
      'id': 'canonical-id',
      'legacyId': 'receipt-id',
      'sender': 'VK-HDFCBK',
      'body': 'Spent Rs 100',
      'receivedAtEpochMillis': receivedAt.millisecondsSinceEpoch,
    });
    expect(compatiblePayload.legacyId, 'receipt-id');
    expect(compatiblePayload.identityIds, {'canonical-id', 'receipt-id'});
    expect(
      () => decodeRawSmsPayload({
        'id': 'canonical-id',
        'legacyId': '  ',
        'sender': 'VK-HDFCBK',
        'body': 'Spent Rs 100',
        'receivedAtEpochMillis': receivedAt.millisecondsSinceEpoch,
      }),
      throwsA(isA<StateError>()),
    );
  });

  Future<void> waitForCaptureReady(ProviderContainer container) async {
    await container.read(smsPermissionControllerProvider.future);
    await container.read(appDatabaseProvider.future);
    await container.read(parserCascadeProvider.future);
    await container.read(categorizerProvider.future);
    await container.read(messageKindClassifierProvider.future);
    await pumpEventQueue();
  }

  test('ingests channel SMS into raw_sms and transactions on parse success',
      () async {
    final controller = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        parserCascadeProvider.overrideWith(
          (ref) async => FakeParserCascade.ok(
            NormalizedTransactionRecord(
              amount: 449,
              currencyCode: 'USD',
              currencySymbol: r'$',
              direction: TransactionDirection.debit,
              channel: TransactionChannel.upi,
              merchantRaw: 'AMZN*MKTPLC',
              counterpartyVpa: null,
              accountHint: 'xx4521',
              balanceAfter: 12384.5,
              refId: '615223847712',
              ts: DateTime.utc(2026, 7, 5, 10, 30),
              parseSource: ParseSource.template,
              parseConfidence: 0.97,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    controller.add({
      'id': 'sms_live_1',
      'sender': 'VK-HDFCBK',
      'body': 'Spent USD 449',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 7, 5, 10, 31).millisecondsSinceEpoch,
    });
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));
    expect(rawRows.single.id, 'sms_live_1');
    expect(rawRows.single.processed, isTrue);

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_sms_live_1');
    expect(transactions.single.smsId, 'sms_live_1');
    expect(transactions.single.amount, 449);
    expect(transactions.single.currencyCode, 'USD');
    expect(transactions.single.currencySymbol, r'$');
    expect(transactions.single.direction, 'debit');
    expect(transactions.single.channel, 'upi');
    expect(transactions.single.status, 'needs_review');
    // T-039: the ingest pipeline runs the categorizer ladder — 'AMZN*MKTPLC'
    // hits the bundled seed map ('amzn' -> shopping) at 0.8.
    expect(transactions.single.categoryId, 'shopping');
    final confidence =
        jsonDecode(transactions.single.confidenceJson) as Map<String, Object?>;
    expect(confidence['parser'], {'c': 0.97, 'src': 'template'});
    // Exact names receive stable IDs even when no platform embedding model is
    // available on this widget test host.
    expect(confidence['merchant'], {
      'v': 'AMZN*MKTPLC',
      'c': 1.0,
      'src': 'new',
    });
    expect(confidence['category'], {'c': 0.8, 'src': 'seed'});
  });

  test('numeric phone-like VPA alone stays fallback and reviewable', () async {
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(merchantRaw: null, counterpartyVpa: '9876543210@okaxis'),
    );
    await ingestor.ingest(
      _message(
        'sms_numeric_vpa_review',
        body: 'A/c XX1234 debited by Rs 449 towards 9876543210@okaxis',
      ),
    );

    final transaction =
        await database.select(database.transactions).getSingle();
    final confidence =
        jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
    expect(transaction.categoryId, 'other');
    // The low-confidence fallback remains on the confirmation path.
    expect(transaction.status, 'asked');
    expect(confidence['category'], {'c': .3, 'src': 'fallback'});
  });

  test('description-only user rule applies independently of category guess',
      () async {
    await RuleRepository(database).insert(
      matchType: 'merchant',
      matchValue: 'Corner Store',
      setDescription: 'Household supplies',
    );
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(merchantRaw: 'Corner Store'),
    );
    await ingestor.ingest(
      _message('sms_description_rule', body: 'Rs 449 spent at Corner Store'),
    );

    final transaction =
        await database.select(database.transactions).getSingle();
    final confidence =
        jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
    expect(transaction.description, 'Household supplies');
    expect(transaction.categoryId, 'other');
    expect(transaction.status, 'needs_review');
    expect(confidence['category'], {'c': .3, 'src': 'fallback'});
  });

  test('reminder amount parser accepts terminal sentence punctuation',
      () async {
    final ingestor = SmsIngestor(
      database: database,
      parser: FakeParserCascade.err(),
      messageKindClassifier: _testMessageKindClassifier,
    );
    await ingestor.ingest(
      _message(
        'sms_reminder_terminal_period',
        body: 'Credit card payment due on 15-Jul-2026. Amount: Rs. 500.',
      ),
    );

    final expected = await database.select(database.expectedEvents).getSingle();
    expect(expected.expectedAmountPaise, 50000);
  });

  test(
      'settings emissions do not re-subscribe the capture stream '
      '(regression: T-046 triage — ask-budget watch rebuilt the provider)',
      () async {
    // Single-subscription controller: any second listen() throws
    // "Stream has already been listened to", which is exactly the failure
    // mode this regression test guards against.
    final controller = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        parserCascadeProvider.overrideWith(
          (ref) async => FakeParserCascade.ok(_sampleRecord(amount: 100)),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    controller.add(_channelPayload('sms_before_settings'));
    await pumpEventQueue();

    // Emit a settings change (also covers the controller's initial
    // loading→data transition, which happens during waitForCaptureReady):
    // the capture provider must NOT rebuild/re-listen.
    await container
        .read(appSettingsControllerProvider.notifier)
        .setAskDailyBudget(1);
    await pumpEventQueue();

    controller.add(_channelPayload('sms_after_settings'));
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(
      rawRows.map((row) => row.id),
      containsAll(['sms_before_settings', 'sms_after_settings']),
    );
  });

  test('decision policy marks high amount seed-categorized txn asked',
      () async {
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 500),
      now: () => DateTime.utc(2026, 7, 5, 12),
    );

    await ingestor.ingest(_message('sms_high_amount', body: 'Spent Rs 500'));

    final transactions = await database.select(database.transactions).get();
    expect(transactions.single.status, 'asked');
  });

  test('live and batch replay skip a marked SMS before retaining or parsing',
      () async {
    final now = DateTime.utc(2026, 7, 5, 12);
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_suppressed_replay',
            sender: 'synthetic-bank',
            body: 'Synthetic fixture body',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_sms_suppressed_replay',
            ts: now.millisecondsSinceEpoch,
            amount: 500,
            direction: 'debit',
            channel: 'upi',
            smsId: const Value('sms_suppressed_replay'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final existing = await database.select(database.transactions).getSingle();
    await SmsDispositionRepository(database).markNotTransaction(existing);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals(existing.id)))
        .write(const TransactionsCompanion(smsId: Value(null)));
    await database.delete(database.rawSms).go();

    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 500),
      now: () => now,
    );
    await ingestor.ingest(
      _message('sms_suppressed_replay', body: 'Synthetic fixture body'),
    );
    await ingestor.ingestBatch([
      _message('sms_suppressed_replay', body: 'Synthetic fixture body'),
    ]);

    expect(await database.select(database.transactions).get(), hasLength(1));
    expect(await database.select(database.rawSms).get(), isEmpty);
    expect(await database.select(database.smsDispositions).get(), hasLength(1));
  });

  test('failed message merchant snapshot additions are discarded', () async {
    final first = _sampleRecord(merchantRaw: 'ROUND3 SHOP');
    final records = {
      'sms_merchant_rollback': first,
      'sms_merchant_retry': first,
    };
    await database.customStatement('''
      CREATE TRIGGER fail_first_merchant_transaction
      BEFORE INSERT ON transactions
      WHEN NEW.id = 'txn_sms_merchant_rollback'
      BEGIN
        SELECT RAISE(ABORT, 'synthetic transaction write failure');
      END;
    ''');
    final ingestor = _ingestorFor(
      database,
      null,
      recordsById: records,
      merchantResolver: MerchantResolver(database, const NoopEmbedder()),
    );
    final run = await ingestor.beginMerchantResolutionRun();

    final result = await ingestor.ingestBatch(
      [
        _message('sms_merchant_rollback'),
        _message('sms_merchant_retry'),
      ],
      merchantResolutionRun: run,
    );

    expect(result.failedIds, {'sms_merchant_rollback'});
    expect(result.parsedIds, {'sms_merchant_retry'});
    final transaction =
        await database.select(database.transactions).getSingle();
    expect(transaction.smsId, 'sms_merchant_retry');
    expect(transaction.merchantId, isNotNull);
    expect(
      await (database.select(database.merchants)
            ..where((row) => row.id.equals(transaction.merchantId!)))
          .getSingleOrNull(),
      isNotNull,
    );
  });

  test('persists template id and provenance in parser confidence metadata',
      () async {
    final ingestor = _ingestorFor(
      database,
      NormalizedTransactionRecord(
        amount: 100,
        direction: TransactionDirection.debit,
        channel: TransactionChannel.upi,
        merchantRaw: 'PUBLIC SHOP',
        counterpartyVpa: null,
        accountHint: 'xx1234',
        balanceAfter: null,
        refId: null,
        ts: DateTime.utc(2026, 7, 10),
        parseSource: ParseSource.template,
        parseConfidence: 0.85,
        templateId: 'public_debit_v1',
        templateProvenance: 'public',
      ),
    );

    await ingestor.ingest(_message('sms_public_template'));

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_public_template')))
        .getSingle();
    final confidence =
        jsonDecode(transaction.confidenceJson) as Map<String, Object?>;
    expect(confidence['parser'], {
      'c': 0.85,
      'src': 'template',
      'template_id': 'public_debit_v1',
      'provenance': 'public',
    });
  });

  test('decision policy respects daily ask budget exhaustion', () async {
    final now = DateTime.utc(2026, 7, 5, 12);
    await _insertTransaction(
      database,
      id: 'txn_asked_1',
      status: 'asked',
      createdAt: DateTime.utc(2026, 7, 5, 8),
    );
    await _insertTransaction(
      database,
      id: 'txn_asked_2',
      status: 'asked',
      createdAt: DateTime.utc(2026, 7, 5, 9),
    );
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 500),
      now: () => now,
    );

    await ingestor.ingest(_message('sms_budget_full'));

    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_budget_full')))
        .getSingle();
    expect(txn.status, 'needs_review');
  });

  test('daily ask quota resets at the injected local midnight boundary',
      () async {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final now = DateTime.utc(2026, 7, 5, 18, 31);
    for (final id in [
      'txn_asked_before_midnight_1',
      'txn_asked_before_midnight_2',
      'txn_familiar_before_midnight_1',
      'txn_familiar_before_midnight_2',
      'txn_familiar_before_midnight_3',
    ]) {
      await _insertTransaction(
        database,
        id: id,
        status: id.startsWith('txn_asked') ? 'asked' : 'auto',
        createdAt: DateTime.utc(2026, 7, 5, 18, 29),
        merchantRaw: 'AMZN*MKTPLC',
      );
    }

    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 49),
      now: () => now,
      financialCalendar: calendar,
    );
    await ingestor.ingest(_message('sms_after_local_midnight'));

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_after_local_midnight')))
        .getSingle();
    expect(transaction.status, 'asked');
  });

  test('decision policy asks for familiar merchant at medium confidence',
      () async {
    final now = DateTime.utc(2026, 7, 5, 12);
    for (var i = 0; i < 3; i++) {
      await _insertTransaction(
        database,
        id: 'txn_prior_$i',
        merchantRaw: 'AMZN*MKTPLC',
        status: 'auto',
        createdAt: DateTime.utc(2026, 7, 4, i),
      );
    }
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 49),
      now: () => now,
    );

    await ingestor.ingest(_message('sms_familiar_merchant'));

    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_familiar_merchant')))
        .getSingle();
    expect(txn.status, 'asked');
  });

  test('decision policy keeps rule-backed high confidence txn auto', () async {
    await database.into(database.rules).insert(
          RulesCompanion.insert(
            id: 'rule_amzn',
            matchType: 'merchant_legacy',
            matchValue: 'amzn',
            setCategoryId: const Value('shopping'),
            createdAt: DateTime.utc(2026, 7, 5),
          ),
        );
    final ingestor = _ingestorFor(
      database,
      _sampleRecord(amount: 49),
      now: () => DateTime.utc(2026, 7, 5, 12),
    );

    await ingestor.ingest(_message('sms_rule_auto'));

    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_rule_auto')))
        .getSingle();
    expect(txn.status, 'auto');
  });

  test('similarity merchant alias keeps rule hit in review', () async {
    final now = DateTime.utc(2026, 7, 5);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_swiggy',
            canonicalName: 'Swiggy',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: 'SWIGGYX',
            merchantId: 'merchant_swiggy',
            source: 'similarity',
            confidence: 0.8,
          ),
        );
    await RuleRepository(database).insert(
      matchType: 'merchant',
      matchValue: 'SwiggyX',
      setCategoryId: 'shopping',
      clock: () => now,
    );

    await _ingestorFor(
      database,
      _sampleRecord(merchantRaw: 'SwiggyX'),
      merchantResolver: MerchantResolver(database, const NoopEmbedder()),
      now: () => now,
    ).ingest(_message('sms_similarity_rule'));

    final txn = await (database.select(database.transactions)
          ..where((row) => row.smsId.equals('sms_similarity_rule')))
        .getSingle();
    expect(txn.status, 'needs_review');
    expect(txn.merchantId, isNull);
    final confidence = jsonDecode(txn.confidenceJson) as Map<String, Object?>;
    final merchant = confidence['merchant']! as Map<String, Object?>;
    expect(merchant['src'], 'suggestion');
    expect(merchant['suggested_merchant_id'], 'merchant_swiggy');
  });

  test('decision policy asks once then auto-classifies a seen counterparty',
      () async {
    await database.into(database.rules).insert(
          RulesCompanion.insert(
            id: 'rule_friend',
            matchType: 'merchant_legacy',
            matchValue: 'amzn',
            setCategoryId: const Value('shopping'),
            createdAt: DateTime.utc(2026, 7, 5),
          ),
        );
    final ingestor = _ingestorFor(
      database,
      null,
      recordsById: {
        'sms_first_friend': _sampleRecord(
          amount: 49,
          counterpartyVpa: 'friend@upi',
          ts: DateTime.utc(2026, 7, 5, 10, 30),
        ),
        'sms_second_friend': _sampleRecord(
          amount: 49,
          counterpartyVpa: 'friend@upi',
          ts: DateTime.utc(2026, 7, 5, 10, 45),
        ),
      },
      now: () => DateTime.utc(2026, 7, 5, 12),
    );

    await ingestor.ingest(_message('sms_first_friend'));
    await ingestor.ingest(_message('sms_second_friend'));

    final transactions = await (database.select(database.transactions)
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
    expect(transactions.map((row) => row.status), [
      'asked',
      'auto',
    ]);
  });

  test('leaves raw_sms unparsed when parser returns an expected miss',
      () async {
    final controller = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        parserCascadeProvider
            .overrideWith((ref) async => FakeParserCascade.err()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    controller.add({
      'id': 'sms_live_2',
      'sender': 'VK-HDFCBK',
      'body': 'Unrecognized message',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 7, 5, 11, 0).millisecondsSinceEpoch,
    });
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));
    expect(rawRows.single.id, 'sms_live_2');
    expect(rawRows.single.processed, isFalse);

    final transactions = await database.select(database.transactions).get();
    expect(transactions, isEmpty);
  });

  test('persists an unparsed reason and skips same-version retry', () async {
    final parser = FakeParserCascade.ok(_sampleRecord())
      ..setError(ParseFailure.unparsed);
    final ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    );
    final sms = _message('sms_unparsed_reason');

    await ingestor.ingest(sms);
    final first = (await database.select(database.rawSms).get()).single;
    expect(first.parserVersion, smsParserVersion);
    expect(first.failureReason, SmsFailureReason.unparsed);
    expect(first.failureReason, isNot(contains(sms.body)));
    expect(parser.parseCalls, 1);

    await ingestor.ingest(sms);

    expect(parser.parseCalls, 1);
  });

  test('an unclassified message fails closed before parser or LLM fallback',
      () async {
    final parser = FakeParserCascade.ok(_sampleRecord());
    final ingestor = SmsIngestor(database: database, parser: parser);
    final sms = _message(
      'sms_unclassified',
      body: 'Your monthly account snapshot lists INR 400 in total activity.',
    );

    await ingestor.ingest(sms);

    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), isEmpty);
    final raw = (await database.select(database.rawSms).get()).single;
    expect(raw.processed, isFalse);
    expect(raw.failureReason, SmsFailureReason.unparsed);
  });

  test('classifier direction must agree with extracted direction', () async {
    final parser = FakeParserCascade.ok(
      NormalizedTransactionRecord(
        amount: 449,
        direction: TransactionDirection.credit,
        channel: TransactionChannel.upi,
        merchantRaw: 'SANITIZED SHOP',
        counterpartyVpa: null,
        accountHint: 'xx1234',
        balanceAfter: null,
        refId: null,
        ts: DateTime.utc(2026, 7, 5, 10, 30),
        parseSource: ParseSource.localLlm,
        parseConfidence: 0.6,
      ),
    );
    final ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    );

    await ingestor.ingest(
      _message(
        'sms_direction_mismatch',
        body: 'INR 449.00 debited from A/c XX1234 via UPI at SANITIZED SHOP.',
      ),
    );

    expect(await database.select(database.transactions).get(), isEmpty);
    final raw = (await database.select(database.rawSms).get()).single;
    expect(raw.failureReason, SmsFailureReason.unparsed);
  });

  test('non-settled cue also rejects contradictory extracted direction',
      () async {
    final parser = FakeParserCascade.ok(
      NormalizedTransactionRecord(
        amount: 500,
        direction: TransactionDirection.credit,
        channel: TransactionChannel.upi,
        merchantRaw: null,
        counterpartyVpa: null,
        accountHint: 'xx1234',
        balanceAfter: null,
        refId: null,
        ts: DateTime.utc(2026, 7, 5, 10, 30),
        parseSource: ParseSource.localLlm,
        parseConfidence: 0.4,
      ),
    );
    final ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    );

    await ingestor.ingest(
      _message(
        'sms_failed_direction_mismatch',
        body: 'INR 500.00 debited from A/c XX1234; transaction declined.',
      ),
    );

    expect(await database.select(database.transactions).get(), isEmpty);
    final raw = (await database.select(database.rawSms).get()).single;
    expect(raw.failureReason, SmsFailureReason.unparsed);
  });

  test(
      'generic-only model-unavailable ingest keeps supported payment review-only and abstains on lifecycle negatives',
      () async {
    final ingestor = SmsIngestor(
      database: database,
      parser: const ParserCascade(
        templateMatcher: TemplateMatcher(registries: []),
      ),
      messageKindClassifier: _testMessageKindClassifier,
    );
    final messages = [
      _message(
        'sms_generic_charge',
        body: 'Your card XX1234 was charged Rs. 725.00 at SANITIZED STORE',
      ),
      _message(
        'sms_generic_failed',
        body: 'A/c XX1234 failed for Rs. 500.00 via UPI',
      ),
      _message(
        'sms_generic_reversal',
        body: 'Reversal of INR 300.00 credited back to A/c XX1234',
      ),
      _message(
        'sms_generic_future',
        body: 'Rs. 500 will be debited from A/c XX1234 tomorrow via UPI',
      ),
    ];

    for (final message in messages) {
      await ingestor.ingest(message);
    }

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_sms_generic_charge');
    expect(transactions.single.status, 'needs_review');
    // This intentionally exercises only the generic parser with the model
    // unavailable; production provider lifecycle guarding remains T-183.
    expect(transactions.single.messageKind, 'settledDebit');
    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(messages.length));
    for (final raw in rawRows.where((row) => row.id != 'sms_generic_charge')) {
      expect(raw.processed, isFalse, reason: raw.id);
      expect(raw.failureReason, SmsFailureReason.unparsed, reason: raw.id);
    }
  });

  test('classifier upgrade retries retained failures by default', () async {
    final parser = FakeParserCascade.ok(_sampleRecord())
      ..setError(ParseFailure.unparsed);
    final sms = _message('sms_retry_after_upgrade');
    await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
      parserVersion: smsParserVersion - 1,
    ).ingest(sms);

    parser.setError(null);
    final upgraded = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    );
    await upgraded.ingest(sms);

    final raw = (await database.select(database.rawSms).get()).single;
    expect(raw.parserVersion, smsParserVersion);
    expect(raw.failureReason, isNull);
    expect(raw.processed, isTrue);
    expect(parser.parseCalls, 2);
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test('persists processing errors without exception text', () async {
    final parser = FakeParserCascade.ok(_sampleRecord())
      ..setProcessingError(StateError('private parser detail'));
    final sms = _message('sms_processing_error');

    await expectLater(
      SmsIngestor(
        database: database,
        parser: parser,
        messageKindClassifier: _testMessageKindClassifier,
      ).ingest(sms),
      throwsA(isA<StateError>()),
    );

    final raw = (await database.select(database.rawSms).get()).single;
    expect(raw.parserVersion, smsParserVersion);
    expect(raw.failureReason, SmsFailureReason.processingError);
    expect(raw.failureReason, isNot(contains('private parser detail')));
    expect(raw.failureReason, isNot(contains(sms.body)));

    parser.setProcessingError(null);
    await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingest(sms);
    expect(parser.parseCalls, 2);
    expect(await database.select(database.transactions).get(), hasLength(1));
  });

  test('batch attempts one repeated failing SMS id once without false success',
      () async {
    final parser = FakeParserCascade.ok(_sampleRecord())
      ..setProcessingError(StateError('simulated parser failure'));
    final sms = _message('sms_repeated_failure');
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([sms, sms]);

    expect(parser.parseCalls, 1);
    expect(result.failed, 1);
    expect(result.failedIds, {'sms_repeated_failure'});
    expect(result.succeededIds, isEmpty);
    expect(result.alreadyKnownIds, isEmpty);
    expect(
      result.failedIds.intersection(result.succeededIds),
      isEmpty,
    );
  });

  test('shared run failure set counts repeated same-page ID once', () async {
    final parser = FakeParserCascade.ok(_sampleRecord())
      ..setProcessingError(StateError('simulated parser failure'));
    final sms = _message('sms_shared_repeated_failure');
    final attemptedFailures = <String>{};
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch(
      [sms, sms],
      failedIdsAlreadyAttemptedThisRun: attemptedFailures,
    );

    expect(parser.parseCalls, 1);
    expect(attemptedFailures, {'sms_shared_repeated_failure'});
    expect(result.failed, 1);
    expect(result.failedIds, {'sms_shared_repeated_failure'});
    expect(result.succeededIds, isEmpty);
    expect(result.alreadyKnownIds, isEmpty);
    expect(result.failedIds.intersection(result.succeededIds), isEmpty);
    expect(result.failedIds.intersection(result.alreadyKnownIds), isEmpty);
  });

  test('shared run failure set counts repeated identity conflict once',
      () async {
    final parser = FakeParserCascade.ok(_sampleRecord());
    final sms = _message('sms_shared_repeated_conflict');
    final attemptedFailures = <String>{};
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch(
      [sms, sms],
      additionalIdentityConflictIds: {sms.id},
      failedIdsAlreadyAttemptedThisRun: attemptedFailures,
    );

    expect(parser.parseCalls, 0);
    expect(attemptedFailures, {'sms_shared_repeated_conflict'});
    expect(result.failed, 1);
    expect(result.failedIds, {'sms_shared_repeated_conflict'});
    expect(result.succeededIds, isEmpty);
    expect(result.alreadyKnownIds, isEmpty);
  });

  test('processed raw evidence from an older parser version is replayable',
      () async {
    final sms = _message('sms_old_processed_replay');
    await _insertIdentityRaw(
      database,
      id: sms.id,
      sender: sms.sender,
      body: sms.body,
      receivedAt: sms.receivedAt,
      processed: true,
      parserVersion: smsParserVersion - 1,
    );
    final parser = FakeParserCascade.ok(_sampleRecord());

    await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingest(sms);

    expect(parser.parseCalls, 1);
    expect(await database.select(database.transactions).get(), hasLength(1));
    final raw = await database.select(database.rawSms).getSingle();
    expect(raw.parserVersion, smsParserVersion);
    expect(raw.processed, isTrue);
  });

  test('history identity keeps legacy transaction and disposition claims',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    const sender = 'VK-HDFCBK';
    const body = 'Spent Rs 449';
    await _insertIdentityRaw(
      database,
      id: 'legacy_transaction',
      sender: sender,
      body: body,
      receivedAt: receivedAt,
      processed: true,
    );
    await _insertIdentityTransaction(
      database,
      id: 'txn_legacy_transaction',
      smsId: 'legacy_transaction',
      isDeleted: true,
    );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'legacy_disposition',
            transactionId: 'txn_legacy_disposition',
            disposition: 'not_transaction',
            createdAt: receivedAt,
          ),
        );
    final originalTransaction =
        await database.select(database.transactions).getSingle();
    final originalRaw = await database.select(database.rawSms).getSingle();
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_transaction',
        legacyId: 'legacy_transaction',
        sender: sender,
        body: body,
        receivedAt: receivedAt.add(const Duration(minutes: 1)),
      ),
      RawSms(
        id: 'canonical_disposition',
        legacyId: 'legacy_disposition',
        sender: sender,
        body: body,
        receivedAt: receivedAt.add(const Duration(minutes: 1)),
      ),
    ]);

    expect(result.failed, 0);
    expect(result.alreadyKnownIds, {
      'canonical_transaction',
      'canonical_disposition',
    });
    expect(result.parsedIds, isEmpty);
    expect(result.unparsedIds, isEmpty);
    expect(parser.parseCalls, 0);
    expect(
      await database.select(database.transactions).get(),
      [originalTransaction],
    );
    expect(await database.select(database.rawSms).get(), [originalRaw]);
    expect(await database.select(database.smsDispositions).get(), hasLength(1));
  });

  test('source-null and nonstandard-ID legacy transactions remain known',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityTransaction(
      database,
      id: 'txn_legacy_source_missing',
      smsId: null,
      isDeleted: true,
    );
    await _insertIdentityRaw(
      database,
      id: 'legacy_arbitrary_source',
      sender: 'VK-HDFCBK',
      body: 'Spent Rs 449',
      receivedAt: receivedAt,
      processed: true,
    );
    await _insertIdentityTransaction(
      database,
      id: 'restored_custom_transaction_id',
      smsId: 'legacy_arbitrary_source',
    );
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_source_missing',
        legacyId: 'legacy_source_missing',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
      RawSms(
        id: 'canonical_arbitrary_source',
        legacyId: 'legacy_arbitrary_source',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 0);
    expect(result.alreadyKnownIds, {
      'canonical_source_missing',
      'canonical_arbitrary_source',
    });
    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), hasLength(2));
    expect(
      (await database.select(database.rawSms).get()).single.id,
      'legacy_arbitrary_source',
    );
  });

  test('distinct canonical and legacy transaction claims abstain in batch',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityTransaction(
      database,
      id: 'txn_canonical_conflict',
      smsId: null,
    );
    await _insertIdentityTransaction(
      database,
      id: 'txn_legacy_conflict',
      smsId: null,
    );
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_conflict',
        legacyId: 'legacy_conflict',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 1);
    expect(result.failedIds, {'canonical_conflict'});
    expect(result.alreadyKnownIds, isEmpty);
    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), hasLength(2));
    expect(await database.select(database.rawSms).get(), isEmpty);
  });

  test('batch isolates one identity conflict and imports a valid sibling',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityTransaction(
      database,
      id: 'txn_canonical_isolated',
      smsId: null,
    );
    await _insertIdentityTransaction(
      database,
      id: 'txn_legacy_isolated',
      smsId: null,
    );
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_isolated',
        legacyId: 'legacy_isolated',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
      RawSms(
        id: 'valid_sibling',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 1);
    expect(result.failedIds, {'canonical_isolated'});
    expect(result.succeededIds, {'valid_sibling'});
    expect(result.createdTxnIds, {'txn_valid_sibling'});
    expect(parser.parseCalls, 1);
    expect(
      (await database.select(database.transactions).get())
          .map((transaction) => transaction.id),
      containsAll([
        'txn_canonical_isolated',
        'txn_legacy_isolated',
        'txn_valid_sibling',
      ]),
    );
    expect(
      (await database.select(database.rawSms).get()).map((raw) => raw.id),
      {'valid_sibling'},
    );
  });

  test('batch rejects a shared alias across canonical inputs but keeps sibling',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_collision_a',
        legacyId: 'legacy_shared_collision',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
      RawSms(
        id: 'canonical_collision_b',
        legacyId: 'legacy_shared_collision',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
      RawSms(
        id: 'valid_after_collision',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 2);
    expect(
      result.failedIds,
      {'canonical_collision_a', 'canonical_collision_b'},
    );
    expect(result.succeededIds, {'valid_after_collision'});
    expect(parser.parseCalls, 1);
    expect(
      (await database.select(database.transactions).get())
          .map((transaction) => transaction.id),
      {'txn_valid_after_collision'},
    );
    expect(
      (await database.select(database.rawSms).get()).map((raw) => raw.id),
      {'valid_after_collision'},
    );
  });

  test('batch rejects inconsistent repeated canonical payloads before writes',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_inconsistent',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
      RawSms(
        id: 'canonical_inconsistent',
        sender: 'VK-HDFCBK',
        body: 'Different synthetic body',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 1);
    expect(result.failedIds, {'canonical_inconsistent'});
    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(await database.select(database.rawSms).get(), isEmpty);
  });

  test('two stored transactions claiming one exact identity abstain', () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityTransaction(
      database,
      id: 'txn_same_claim',
      smsId: null,
    );
    await _insertIdentityRaw(
      database,
      id: 'same_claim',
      sender: 'VK-HDFCBK',
      body: 'Spent Rs 449',
      receivedAt: receivedAt,
      processed: true,
    );
    await _insertIdentityTransaction(
      database,
      id: 'restored_other_claim',
      smsId: 'same_claim',
    );
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'same_claim',
        legacyId: 'other_candidate',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 1);
    expect(result.alreadyKnownIds, isEmpty);
    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), hasLength(2));
    expect(
      (await database.select(database.rawSms).get()).single.id,
      'same_claim',
    );
  });

  test('transaction and unrelated disposition claims abstain', () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityTransaction(
      database,
      id: 'txn_disposition_conflict',
      smsId: null,
    );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'disposition_conflict',
            transactionId: 'different_transaction',
            disposition: 'not_transaction',
            createdAt: receivedAt,
          ),
        );
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'disposition_conflict',
        legacyId: 'disposition_conflict_legacy',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: receivedAt,
      ),
    ]);

    expect(result.failed, 1);
    expect(result.alreadyKnownIds, isEmpty);
    expect(parser.parseCalls, 0);
    expect(await database.select(database.transactions).get(), hasLength(1));
    expect(await database.select(database.rawSms).get(), isEmpty);
    expect(await database.select(database.smsDispositions).get(), hasLength(1));
  });

  test('identity conflict leaves mismatched retained raw bytes unchanged',
      () async {
    final receivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    await _insertIdentityRaw(
      database,
      id: 'legacy_mismatched',
      sender: 'VK-OTHERBANK',
      body: 'Different synthetic alert',
      receivedAt: receivedAt,
      processed: false,
      parserVersion: smsParserVersion - 1,
    );
    final originalRaw = await database.select(database.rawSms).getSingle();
    final parser = FakeParserCascade.ok(_sampleRecord());
    final ingestor = SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    );

    await expectLater(
      ingestor.ingest(
        RawSms(
          id: 'canonical_mismatched',
          legacyId: 'legacy_mismatched',
          sender: 'VK-HDFCBK',
          body: 'Spent Rs 449',
          receivedAt: receivedAt,
        ),
      ),
      throwsA(isA<Exception>()),
    );

    expect(await database.select(database.rawSms).get(), [originalRaw]);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(parser.parseCalls, 0);
  });

  test(
      'exact dual retained aliases replay under canonical ID without date drift',
      () async {
    final legacyReceivedAt = DateTime.utc(2026, 7, 5, 10, 31);
    final canonicalReceivedAt =
        legacyReceivedAt.add(const Duration(minutes: 1));
    for (final id in ['canonical_replay', 'legacy_replay']) {
      await _insertIdentityRaw(
        database,
        id: id,
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: legacyReceivedAt,
        processed: false,
        parserVersion: smsParserVersion - 1,
      );
    }
    final parser = FakeParserCascade.ok(_sampleRecord());
    final result = await SmsIngestor(
      database: database,
      parser: parser,
      messageKindClassifier: _testMessageKindClassifier,
    ).ingestBatch([
      RawSms(
        id: 'canonical_replay',
        legacyId: 'legacy_replay',
        sender: 'VK-HDFCBK',
        body: 'Spent Rs 449',
        receivedAt: canonicalReceivedAt,
      ),
    ]);

    final rawRows = await database.select(database.rawSms).get();
    final transactions = await database.select(database.transactions).get();
    expect(result.failed, 0);
    expect(parser.parseCalls, 1);
    expect(rawRows.map((row) => row.id).toSet(), {
      'canonical_replay',
      'legacy_replay',
    });
    expect(
      rawRows.singleWhere((row) => row.id == 'canonical_replay').receivedAt,
      legacyReceivedAt.toLocal(),
    );
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_canonical_replay');
    expect(transactions.single.smsId, 'canonical_replay');
    expect(transactions.single.refId, isNull);
    expect(transactions.single.counterpartyVpa, isNull);
  });

  test('reprocessing the same SMS id is idempotent (no duplicate rows)',
      () async {
    final controller = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        parserCascadeProvider.overrideWith(
          (ref) async => FakeParserCascade.ok(
            NormalizedTransactionRecord(
              amount: 449,
              direction: TransactionDirection.debit,
              channel: TransactionChannel.upi,
              merchantRaw: 'AMZN*MKTPLC',
              counterpartyVpa: null,
              accountHint: 'xx4521',
              balanceAfter: 12384.5,
              refId: '615223847712',
              ts: DateTime.utc(2026, 7, 5, 10, 30),
              parseSource: ParseSource.template,
              parseConfidence: 0.97,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    final payload = {
      'id': 'sms_dupe',
      'sender': 'VK-HDFCBK',
      'body': 'Spent Rs 449',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 7, 5, 10, 31).millisecondsSinceEpoch,
    };
    controller.add(payload);
    await pumpEventQueue();
    controller.add(payload);
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_sms_dupe');
  });

  test('re-import preserves edited and soft-deleted transaction state',
      () async {
    final original = _sampleRecord(amount: 449, merchantRaw: 'ORIGINAL');
    final ingestor = _ingestorFor(database, original);
    final sms = _message('sms_user_edited');
    await ingestor.ingest(sms);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('txn_sms_user_edited')))
        .write(
      const TransactionsCompanion(
        amount: Value(777),
        merchantRaw: Value('USER EDIT'),
        status: Value('confirmed'),
        isDeleted: Value(true),
        smsId: Value(null),
      ),
    );
    await (database.delete(database.rawSms)
          ..where((row) => row.id.equals('sms_user_edited')))
        .go();

    final changedParser = _ingestorFor(
      database,
      _sampleRecord(amount: 999, merchantRaw: 'NEW PARSER VALUE'),
    );
    await changedParser.ingest(sms);

    final transaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_sms_user_edited')))
        .getSingle();
    expect(transaction.amount, 777);
    expect(transaction.merchantRaw, 'USER EDIT');
    expect(transaction.status, 'confirmed');
    expect(transaction.isDeleted, isTrue);
    expect(await database.select(database.rawSms).get(), isEmpty);
  });

  test(
      'suppresses a wallet SMS echo of an already-ingested bank debit '
      '(T-025)', () async {
    final controller = StreamController<Object?>();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        parserCascadeProvider.overrideWith(
          (ref) async => FakeParserCascade.byId({
            // Bank UPI-debit alert: only a VPA, no merchant text.
            'sms_bank': NormalizedTransactionRecord(
              amount: 449,
              direction: TransactionDirection.debit,
              channel: TransactionChannel.upi,
              merchantRaw: null,
              counterpartyVpa: 'amazon@ybl',
              accountHint: 'xx4521',
              balanceAfter: 12384.5,
              refId: null,
              ts: DateTime.utc(2026, 7, 5, 10, 30),
              parseSource: ParseSource.template,
              parseConfidence: 0.97,
            ),
            // Wallet app's own notification for the same payment, 3 minutes
            // later, with merchant text instead of a VPA.
            'sms_wallet': NormalizedTransactionRecord(
              amount: 449,
              direction: TransactionDirection.debit,
              channel: TransactionChannel.wallet,
              merchantRaw: 'Amazon Pay India',
              counterpartyVpa: null,
              accountHint: null,
              balanceAfter: null,
              refId: null,
              ts: DateTime.utc(2026, 7, 5, 10, 33),
              parseSource: ParseSource.template,
              parseConfidence: 0.9,
            ),
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    controller.add({
      'id': 'sms_bank',
      'sender': 'VK-HDFCBK',
      'body': 'A/c debited by Rs.449 towards amazon@ybl',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 7, 5, 10, 30).millisecondsSinceEpoch,
    });
    await pumpEventQueue();
    controller.add({
      'id': 'sms_wallet',
      'sender': 'AM-PAYTM',
      'body': 'Paid Rs.449 to Amazon Pay India',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 7, 5, 10, 33).millisecondsSinceEpoch,
    });
    await pumpEventQueue();

    final transactions = await (database.select(database.transactions)
          ..orderBy([(row) => OrderingTerm.asc(row.ts)]))
        .get();
    expect(transactions, hasLength(2));
    expect(transactions[0].id, 'txn_sms_bank');
    expect(transactions[0].isDeleted, isFalse);
    expect(transactions[0].duplicateOfTxnId, isNull);
    expect(transactions[1].id, 'txn_sms_wallet');
    expect(transactions[1].isDeleted, isFalse);
    expect(transactions[1].duplicateOfTxnId, 'txn_sms_bank');
  });

  test('body-dated transaction pairs with an undated echo within ten minutes',
      () async {
    const calendar = FinancialCalendar.fixed(Duration.zero);
    const normalizer = FieldNormalizer(calendar: calendar);
    final bodyDatedAt = DateTime.utc(2026, 7, 5, 10, 30);
    final echoAt = DateTime.utc(2026, 7, 5, 10, 35);
    final records = {
      'sms_dated': _sampleRecord(
        ts: normalizer.parseDate(
          value: '05-07-26',
          format: 'dd-MM-yy',
          receivedAt: bodyDatedAt,
        ),
      ),
      'sms_undated_echo': _sampleRecord(ts: echoAt),
    };
    final embedder = _CountingEmbedder();
    final ingestor = _ingestorFor(
      database,
      null,
      recordsById: records,
      financialCalendar: calendar,
      merchantResolver: MerchantResolver(database, embedder),
    );

    await ingestor.ingest(
      _messageAt(
        'sms_dated',
        bodyDatedAt,
        body: 'Rs 449 paid to Amazon on 05-07-26',
      ),
    );
    await ingestor.ingest(
      _messageAt('sms_undated_echo', echoAt, body: 'Rs 449 paid to Amazon'),
    );

    final transactions = await (database.select(database.transactions)
          ..orderBy([(row) => OrderingTerm.asc(row.ts)]))
        .get();
    expect(transactions, hasLength(2));
    expect(transactions.first.ts, bodyDatedAt.millisecondsSinceEpoch);
    expect(transactions.last.ts, echoAt.millisecondsSinceEpoch);
    expect(transactions.last.duplicateOfTxnId, transactions.first.id);
    expect(embedder.calls, 1);
  });

  test('same body date over ten minutes apart does not establish identity',
      () async {
    const calendar = FinancialCalendar.fixed(Duration.zero);
    const normalizer = FieldNormalizer(calendar: calendar);
    final firstAt = DateTime.utc(2026, 7, 5, 10, 30);
    final secondAt = DateTime.utc(2026, 7, 5, 10, 45);
    final records = {
      'sms_same_date_a': _sampleRecord(
        ts: normalizer.parseDate(
          value: '05-07-26',
          format: 'dd-MM-yy',
          receivedAt: firstAt,
        ),
      ),
      'sms_same_date_b': _sampleRecord(
        ts: normalizer.parseDate(
          value: '05-07-26',
          format: 'dd-MM-yy',
          receivedAt: secondAt,
        ),
      ),
    };
    final ingestor = _ingestorFor(
      database,
      null,
      recordsById: records,
      financialCalendar: calendar,
    );

    await ingestor.ingest(
      _messageAt(
        'sms_same_date_a',
        firstAt,
        body: 'Rs 449 paid to Amazon on 05-07-26',
      ),
    );
    await ingestor.ingest(
      _messageAt(
        'sms_same_date_b',
        secondAt,
        body: 'Rs 449 paid to Amazon on 05-07-26',
      ),
    );

    final transactions = await (database.select(database.transactions)
          ..orderBy([(row) => OrderingTerm.asc(row.ts)]))
        .get();
    expect(transactions, hasLength(2));
    expect(transactions.first.ts, firstAt.millisecondsSinceEpoch);
    expect(transactions.last.ts, secondAt.millisecondsSinceEpoch);
    expect(transactions.every((row) => row.duplicateOfTxnId == null), isTrue);
  });

  test(
      'production capture keeps real payment fixtures past lifecycle cues '
      'and security footers', () async {
    final controller = StreamController<Object?>();
    const fixtures = [
      'sbi/sbi_debit_dearupi_01',
      'centbk/centbk_debit_02',
      'centbk/centbk_debit_03',
      'centbk/centbk_debit_04',
      'centbk/centbk_credit_lakh_balance',
      'indusind/indusb_credit_02',
      'indusind/indusb_credit_03',
    ];
    final container = ProviderContainer(
      overrides: [
        financialCalendarProvider.overrideWithValue(
          const FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
        ),
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    for (final fixture in fixtures) {
      final expected = jsonDecode(
        File('test/fixtures/sms/$fixture.expected.json').readAsStringSync(),
      ) as Map<String, Object?>;
      controller.add({
        'id': 'sms_${fixture.split('/').last}',
        'sender': expected['sender'],
        'body': File('test/fixtures/sms/$fixture.txt').readAsStringSync(),
        'receivedAtEpochMillis': expected['received_at'],
      });
      await pumpEventQueue();
    }
    controller.add({
      'id': 'sms_otp_authorization',
      'sender': 'TESTBANK',
      'body':
          'Your OTP to authorize a debit transaction of Rs. 500. Do not share.',
      'receivedAtEpochMillis': DateTime.utc(2026, 7, 5).millisecondsSinceEpoch,
    });
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(fixtures.length + 1));
    expect(rawRows.every((row) => row.processed), isTrue);

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(fixtures.length));
    for (final fixture in fixtures) {
      final expected = jsonDecode(
        File('test/fixtures/sms/$fixture.expected.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final record = (expected['expected']! as Map<String, Object?>)['ok']!
          as Map<String, Object?>;
      final smsId = 'sms_${fixture.split('/').last}';
      final transaction = transactions.singleWhere(
        (row) => row.id == 'txn_$smsId',
      );
      expect(transaction.amount, record['amount'], reason: fixture);
      expect(transaction.direction, record['direction'], reason: fixture);
      expect(transaction.lifecycleState, 'settled', reason: fixture);
      expect(
        transaction.messageKind,
        record['direction'] == 'credit' ? 'settledCredit' : 'settledDebit',
        reason: fixture,
      );
      if (fixture == 'sbi/sbi_debit_dearupi_01') {
        expect(transaction.channel, record['channel']);
        expect(transaction.merchantRaw, record['merchant_raw']);
        expect(transaction.accountHint, record['account_hint']);
        expect(transaction.refId, record['ref_id']);
        expect(
          transaction.ts,
          DateTime.utc(2023, 11, 7)
              .subtract(const Duration(hours: 5, minutes: 30))
              .millisecondsSinceEpoch,
        );
      }
      if (fixture == 'centbk/centbk_credit_lakh_balance') {
        expect(transaction.amount, 150);
        expect(transaction.direction, 'credit');
      }
    }
    expect(
      transactions.any((row) => row.id == 'txn_sms_otp_authorization'),
      isFalse,
    );
  });

  test('live provider gates non-transactions and keeps model lifecycle labels',
      () async {
    final controller = StreamController<Object?>();
    final model = AdversarialLlmRuntime((prompt) {
      if (prompt.contains('INR 500.00')) {
        return {
          'amount_text': 'INR 500.00',
          'direction_text': 'debited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 880.00')) {
        return {
          'amount_text': 'INR 880.00',
          'direction_text': 'credited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 300.00')) {
        return {
          'amount_text': 'INR 300.00',
          'direction_text': 'credited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 200.00')) {
        return {
          'amount_text': 'INR 200.00',
          'direction_text': 'debited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 449.00')) {
        return {
          'amount_text': 'INR 449.00',
          'direction_text': 'debited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 700.00')) {
        return {
          'amount_text': 'INR 700.00',
          'direction_text': 'debited',
          'message_kind': 'transactional',
        };
      }
      if (prompt.contains('INR 1,250.00')) {
        return {
          'amount_text': 'INR 1,250.00',
          'direction_text': 'credited',
          'message_kind': 'transactional',
        };
      }
      return {
        'amount_text': 'INR 400',
        'direction_text': 'debited',
        'message_kind': 'transactional',
      };
    });
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        llmRuntimeProvider.overrideWithValue(model),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    final bodies = <String, String>{
      'sms_live_debit_balance':
          'INR 449.00 debited from A/c XX1234 via UPI at SANITIZED SHOP. '
              'Available balance INR 1,500.00.',
      'sms_live_debit_with_rewards_footer':
          'INR 700.00 debited from A/c XX1234 via UPI at SYNTHETIC SHOP. '
              'Earn 3 points on every Rs 100 spent. Apply: example.test',
      'sms_live_credit_balance':
          'INR 1,250.00 credited to A/c XX1234 from SANITIZED PAYROLL. '
              'Available balance INR 15,200.00.',
      'sms_live_failed':
          'INR 500.00 was debited from A/c XX1234 via UPI; transaction declined.',
      'sms_live_direction_mismatch':
          'INR 880.00 was debited from A/c XX1234 via UPI; transaction declined.',
      'sms_live_reversal':
          'INR 300.00 credited back to A/c XX1234 following reversal.',
      'sms_live_pending':
          'INR 200.00 debited from A/c XX1234 via UPI; transaction pending.',
      'sms_live_otp':
          'OTP for transaction INR 500 is 482910. Do not share this code.',
      'sms_live_balance_only':
          'Available balance INR 500.00. Monthly view shows Rs 100 spent this month.',
      'sms_live_rewards_promo':
          'Still spending without rewards? Link SYNTHETIC UPI RuPay CC to earn '
              '3 pts on every Rs 100 spent. Apply: https://example.test',
      'sms_live_unknown':
          'Your monthly account snapshot lists INR 400 in total activity.',
    };
    for (final entry in bodies.entries) {
      controller.add({
        'id': entry.key,
        'sender': 'SYNTHETIC-BANK',
        'body': entry.value,
        'receivedAtEpochMillis':
            DateTime.utc(2026, 9, 28, 12).millisecondsSinceEpoch,
      });
    }
    await pumpEventQueue(times: 20);

    final transactions = await database.select(database.transactions).get();
    final bySmsId = {for (final row in transactions) row.smsId!: row};
    expect(
      bySmsId.keys,
      containsAll(<String>[
        'sms_live_debit_balance',
        'sms_live_debit_with_rewards_footer',
        'sms_live_credit_balance',
        'sms_live_failed',
        'sms_live_reversal',
        'sms_live_pending',
      ]),
    );
    expect(bySmsId.keys, isNot(contains('sms_live_otp')));
    expect(bySmsId.keys, isNot(contains('sms_live_balance_only')));
    expect(bySmsId.keys, isNot(contains('sms_live_rewards_promo')));
    expect(bySmsId.keys, isNot(contains('sms_live_unknown')));
    expect(bySmsId.keys, isNot(contains('sms_live_direction_mismatch')));

    expect(bySmsId['sms_live_debit_balance']!.lifecycleState, 'settled');
    expect(bySmsId['sms_live_debit_balance']!.direction, 'debit');
    expect(
      bySmsId['sms_live_debit_with_rewards_footer']!.lifecycleState,
      'settled',
    );
    expect(bySmsId['sms_live_debit_with_rewards_footer']!.direction, 'debit');
    expect(bySmsId['sms_live_credit_balance']!.lifecycleState, 'settled');
    expect(bySmsId['sms_live_credit_balance']!.direction, 'credit');
    expect(bySmsId['sms_live_failed']!.lifecycleState, 'failed');
    expect(bySmsId['sms_live_failed']!.status, 'needs_review');
    expect(bySmsId['sms_live_reversal']!.lifecycleState, 'reversed');
    expect(bySmsId['sms_live_reversal']!.status, 'needs_review');
    expect(bySmsId['sms_live_pending']!.lifecycleState, 'pending');
    expect(bySmsId['sms_live_pending']!.status, 'needs_review');

    // Only explicit payment candidates and lifecycle records reach the model;
    // promo-only, balance-only, OTP and unknown messages are gated beforehand.
    expect(model.extractCalls, 4);
    expect(
      model.prompts,
      everyElement(isNot(contains('Still spending without rewards'))),
    );
    expect(
      model.prompts,
      everyElement(isNot(contains('Monthly view shows Rs 100 spent'))),
    );
    expect(
      model.prompts,
      everyElement(isNot(contains('Do not share this code'))),
    );
  });

  test('live provider remains safe when the on-device model is unavailable',
      () async {
    final controller = StreamController<Object?>();
    final model = UnavailableLlmRuntime();
    final container = ProviderContainer(
      overrides: [
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
        appDatabaseProvider.overrideWith((ref) async => database),
        capturedSmsSourceProvider.overrideWithValue(
          PlatformCapturedSmsSource(
            channel: FakeCapturedSmsChannel(controller.stream),
          ),
        ),
        llmRuntimeProvider.overrideWithValue(model),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    final bootstrap = container.listen<void>(
      smsCaptureBootstrapProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(bootstrap.close);
    await waitForCaptureReady(container);

    controller.add({
      'id': 'sms_model_unavailable_debit',
      'sender': 'SYNTHETIC-BANK',
      'body': 'INR 725.00 charged on card XX1234 at SANITIZED SHOP.',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 9, 28, 12).millisecondsSinceEpoch,
    });
    controller.add({
      'id': 'sms_model_unavailable_decline',
      'sender': 'SYNTHETIC-BANK',
      'body': 'INR 500.00 debited from A/c XX1234 but transaction declined.',
      'receivedAtEpochMillis':
          DateTime.utc(2026, 9, 28, 12, 1).millisecondsSinceEpoch,
    });
    await pumpEventQueue(times: 20);

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.smsId, 'sms_model_unavailable_debit');
    expect(transactions.single.lifecycleState, 'settled');
    expect(model.extractCalls, 1);
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

SmsIngestor _ingestorFor(
  AppDatabase database,
  NormalizedTransactionRecord? record, {
  Map<String, NormalizedTransactionRecord>? recordsById,
  DateTime Function()? now,
  FinancialCalendar? financialCalendar,
  MerchantResolver? merchantResolver,
}) {
  return SmsIngestor(
    database: database,
    parser: recordsById == null
        ? FakeParserCascade.ok(record!)
        : FakeParserCascade.byId(recordsById),
    messageKindClassifier: _testMessageKindClassifier,
    categorizer: Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap.fromJson('{"amzn":"shopping"}'),
    ),
    merchantResolver: merchantResolver,
    now: now,
    financialCalendar: financialCalendar,
  );
}

final _testMessageKindClassifier = MessageKindClassifier.fromJson(
  File('assets/seed/message_cues_in.json').readAsStringSync(),
);

RawSms _message(String id, {String? body}) {
  return RawSms(
    id: id,
    sender: 'VK-HDFCBK',
    body: body ?? 'Spent Rs 449',
    receivedAt: DateTime.utc(2026, 7, 5, 10, 31),
  );
}

Future<void> _insertIdentityRaw(
  AppDatabase database, {
  required String id,
  required String sender,
  required String body,
  required DateTime receivedAt,
  required bool processed,
  int? parserVersion,
}) {
  return database.into(database.rawSms).insert(
        RawSmsCompanion.insert(
          id: id,
          sender: sender,
          body: body,
          receivedAt: receivedAt,
          processed: Value(processed),
          parserVersion: Value(parserVersion),
          purgeAfter: receivedAt.add(const Duration(days: 30)),
        ),
      );
}

Future<void> _insertIdentityTransaction(
  AppDatabase database, {
  required String id,
  required String? smsId,
  bool isDeleted = false,
}) {
  final timestamp = DateTime.utc(2026, 7, 5, 10, 30);
  return database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: timestamp.millisecondsSinceEpoch,
          amount: 777,
          direction: 'debit',
          channel: 'upi',
          parseSource: 'template',
          smsId: Value(smsId),
          confidenceJson: '{}',
          status: 'confirmed',
          isDeleted: Value(isDeleted),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
}

RawSms _messageAt(String id, DateTime receivedAt, {required String body}) =>
    RawSms(
      id: id,
      sender: 'VK-HDFCBK',
      body: body,
      receivedAt: receivedAt,
    );

/// Raw payload in the shape the native SMS EventChannel emits.
Map<String, Object?> _channelPayload(String id) {
  return {
    'id': id,
    'sender': 'VK-HDFCBK',
    'body': 'Spent Rs 100',
    'receivedAtEpochMillis':
        DateTime.utc(2026, 7, 5, 10, 31).millisecondsSinceEpoch,
  };
}

NormalizedTransactionRecord _sampleRecord({
  double amount = 449,
  String? merchantRaw = 'AMZN*MKTPLC',
  String? counterpartyVpa,
  DateTime? ts,
}) {
  return NormalizedTransactionRecord(
    amount: amount,
    direction: TransactionDirection.debit,
    channel: TransactionChannel.upi,
    merchantRaw: merchantRaw,
    counterpartyVpa: counterpartyVpa,
    accountHint: 'xx4521',
    balanceAfter: 12384.5,
    refId: null,
    ts: ts ?? DateTime.utc(2026, 7, 5, 10, 30),
    parseSource: ParseSource.template,
    parseConfidence: 0.97,
  );
}

Future<void> _insertTransaction(
  AppDatabase database, {
  required String id,
  required String status,
  required DateTime createdAt,
  String? merchantRaw,
  String? counterpartyVpa,
}) {
  return database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: createdAt.millisecondsSinceEpoch,
          amount: 49,
          direction: TransactionDirection.debit.wireName,
          channel: TransactionChannel.upi.wireName,
          merchantRaw: Value(merchantRaw),
          counterpartyVpa: Value(counterpartyVpa),
          parseSource: ParseSource.template.wireName,
          confidenceJson: '{}',
          status: status,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}

class FakeCapturedSmsChannel implements CapturedSmsChannel {
  FakeCapturedSmsChannel(this._stream);

  final Stream<Object?> _stream;

  @override
  Stream<Object?> receiveBroadcastStream() => _stream;
}

class AdversarialLlmRuntime extends LlmRuntime {
  AdversarialLlmRuntime(this._responseForPrompt);

  final Map<String, Object?> Function(String prompt) _responseForPrompt;
  int extractCalls = 0;
  final prompts = <String>[];

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      const LlmSuccess('');

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async {
    extractCalls++;
    prompts.add(prompt);
    return LlmSuccess(_responseForPrompt(prompt));
  }

  @override
  Future<bool> isModelAvailable() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<bool> deleteModel() async => true;
}

class UnavailableLlmRuntime extends LlmRuntime {
  int extractCalls = 0;

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      const LlmUnavailable(LlmUnavailableReason.modelAbsent);

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async {
    extractCalls++;
    return const LlmUnavailable(LlmUnavailableReason.modelAbsent);
  }

  @override
  Future<bool> isModelAvailable() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<bool> deleteModel() async => true;
}

class FakeParserCascade extends ParserCascade {
  FakeParserCascade.ok(this._record)
      : _error = null,
        _recordsById = null,
        super(
          templateMatcher: const TemplateMatcher(registries: []),
        );

  FakeParserCascade.err()
      : _record = null,
        _recordsById = null,
        _error = ParseFailure.unparsed,
        super(
          templateMatcher: const TemplateMatcher(registries: []),
        );

  /// Returns a different fixed record per SMS id, keyed by [RawSms.id].
  FakeParserCascade.byId(this._recordsById)
      : _record = null,
        _error = null,
        super(
          templateMatcher: const TemplateMatcher(registries: []),
        );

  final NormalizedTransactionRecord? _record;
  ParseFailure? _error;
  final Map<String, NormalizedTransactionRecord>? _recordsById;
  Object? _processingError;
  int parseCalls = 0;

  void setError(ParseFailure? error) => _error = error;

  void setProcessingError(Object? error) => _processingError = error;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms, {
    FinancialCalendar? calendar,
  }) async {
    parseCalls++;
    if (_processingError != null) throw _processingError!;
    if (_error != null) return Err(_error!);
    final recordsById = _recordsById;
    var resRecord = recordsById != null ? recordsById[sms.id] : _record;
    if (resRecord != null) {
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

    return Err(_error!);
  }
}
