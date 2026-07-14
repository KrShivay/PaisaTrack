import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

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

  Future<void> waitForCaptureReady(ProviderContainer container) async {
    await container.read(smsPermissionControllerProvider.future);
    await container.read(appDatabaseProvider.future);
    await container.read(parserCascadeProvider.future);
    await container.read(categorizerProvider.future);
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
      'body': 'Spent Rs 449',
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
    expect(transactions.single.direction, 'debit');
    expect(transactions.single.channel, 'upi');
    expect(transactions.single.status, 'needs_review');
    // T-039: the ingest pipeline runs the categorizer ladder — 'AMZN*MKTPLC'
    // hits the bundled seed map ('amzn' -> shopping) at 0.8.
    expect(transactions.single.categoryId, 'shopping');
    final confidence =
        jsonDecode(transactions.single.confidenceJson) as Map<String, Object?>;
    expect(confidence['parser'], {'c': 0.97, 'src': 'template'});
    // T-051: the merchant block now comes from MerchantResolver, not the raw
    // parser record. There's no platform embedder channel in this widget
    // test host, so resolution falls back to 'unembedded' at confidence 0.
    expect(confidence['merchant'], {
      'v': 'AMZN*MKTPLC',
      'c': 0.0,
      'src': 'unembedded',
    });
    expect(confidence['category'], {'c': 0.8, 'src': 'seed'});
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

    await ingestor.ingest(_message('sms_high_amount'));

    final transactions = await database.select(database.transactions).get();
    expect(transactions.single.status, 'asked');
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
            matchType: 'merchant',
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

  test('decision policy asks once for unseen p2p counterparty', () async {
    final ingestor = _ingestorFor(
      database,
      null,
      recordsById: {
        'sms_first_friend': _sampleRecord(
          amount: 49,
          merchantRaw: null,
          counterpartyVpa: 'friend@upi',
          ts: DateTime.utc(2026, 7, 5, 10, 30),
        ),
        'sms_second_friend': _sampleRecord(
          amount: 49,
          merchantRaw: null,
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
      'needs_review',
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

  test(
      'production parser registry ingests a real SBI fixture through '
      'smsCaptureBootstrapProvider', () async {
    final controller = StreamController<Object?>();
    final expected = jsonDecode(
      File('test/fixtures/sms/sbi/sbi_debit_dearupi_01.expected.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final record = (expected['expected']! as Map<String, Object?>)['ok']!
        as Map<String, Object?>;
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
      'id': 'sms_sbi_fixture',
      'sender': expected['sender'],
      'body': File('test/fixtures/sms/sbi/sbi_debit_dearupi_01.txt')
          .readAsStringSync(),
      'receivedAtEpochMillis': expected['received_at'],
    });
    await pumpEventQueue();

    final rawRows = await database.select(database.rawSms).get();
    expect(rawRows, hasLength(1));
    expect(rawRows.single.processed, isTrue);

    final transactions = await database.select(database.transactions).get();
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'txn_sms_sbi_fixture');
    expect(transactions.single.amount, record['amount']);
    expect(transactions.single.direction, record['direction']);
    expect(transactions.single.channel, record['channel']);
    expect(transactions.single.merchantRaw, record['merchant_raw']);
    expect(transactions.single.accountHint, record['account_hint']);
    expect(transactions.single.refId, record['ref_id']);
    expect(transactions.single.ts, record['ts']);
  });
}

SmsIngestor _ingestorFor(
  AppDatabase database,
  NormalizedTransactionRecord? record, {
  Map<String, NormalizedTransactionRecord>? recordsById,
  DateTime Function()? now,
}) {
  return SmsIngestor(
    database: database,
    parser: recordsById == null
        ? FakeParserCascade.ok(record!)
        : FakeParserCascade.byId(recordsById),
    categorizer: Categorizer(
      rules: RuleRepository(database),
      seedMap: SeedCategoryMap.fromJson('{"amzn":"shopping"}'),
    ),
    now: now,
  );
}

RawSms _message(String id) {
  return RawSms(
    id: id,
    sender: 'VK-HDFCBK',
    body: 'Spent Rs 449',
    receivedAt: DateTime.utc(2026, 7, 5, 10, 31),
  );
}

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
  final ParseFailure? _error;
  final Map<String, NormalizedTransactionRecord>? _recordsById;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    final recordsById = _recordsById;
    if (recordsById != null) {
      return Ok(recordsById[sms.id]!);
    }

    final record = _record;
    if (record != null) {
      return Ok(record);
    }

    return Err(_error!);
  }
}
