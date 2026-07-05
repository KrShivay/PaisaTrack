import 'dart:async';

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
        parserCascadeProvider.overrideWithValue(
          FakeParserCascade.ok(
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
    await container.read(smsPermissionControllerProvider.future);

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
        parserCascadeProvider.overrideWithValue(FakeParserCascade.err()),
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
    await container.read(smsPermissionControllerProvider.future);

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
        parserCascadeProvider.overrideWithValue(
          FakeParserCascade.ok(
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
    await container.read(smsPermissionControllerProvider.future);

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
        super(
          templateMatcher: const TemplateMatcher(registries: []),
        );

  FakeParserCascade.err()
      : _record = null,
        _error = ParseFailure.unparsed,
        super(
          templateMatcher: const TemplateMatcher(registries: []),
        );

  final NormalizedTransactionRecord? _record;
  final ParseFailure? _error;

  @override
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    final record = _record;
    if (record != null) {
      return Ok(record);
    }

    return Err(_error!);
  }
}
