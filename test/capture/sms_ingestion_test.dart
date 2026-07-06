import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
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
import 'package:paisatrack/enrichment/categorizer.dart';

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
    expect(transactions.single.status, 'auto');
    // T-039: the ingest pipeline runs the categorizer ladder — 'AMZN*MKTPLC'
    // hits the bundled seed map ('amzn' -> shopping) at 0.8.
    expect(transactions.single.categoryId, 'shopping');
    expect(transactions.single.confidenceJson, contains('"category"'));
    expect(transactions.single.confidenceJson, contains('"src":"seed"'));
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
