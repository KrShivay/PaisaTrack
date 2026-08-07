import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/shadow_pipeline.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('writes normalized shadow rows without changing production rows',
      () async {
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'production_txn',
            ts: DateTime.utc(2026, 8, 7).millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 8, 7),
            updatedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    final runner = ShadowPipelineRunner(
      database,
      now: () => DateTime.utc(2026, 8, 7, 12),
      evaluate: (message) async {
        if (message.id == 'sms_error') throw StateError('test failure');
        return ShadowObservation(
          sourceId: message.id,
          pipelineVersion: 'candidate-v1',
          outcome: message.id == 'sms_unparsed'
              ? ShadowOutcome.unparsed
              : ShadowOutcome.parsed,
          amountPaise: message.id == 'sms_unparsed' ? null : 44900,
          direction: message.id == 'sms_unparsed' ? null : 'debit',
          merchantKey: message.id == 'sms_unparsed' ? null : 'merchant:food',
          categoryId: message.id == 'sms_unparsed' ? null : 'food_dining',
        );
      },
    );

    final result = await runner.run([
      _sms('sms_parsed'),
      _sms('sms_unparsed'),
      _sms('sms_error'),
    ]);

    expect(result.processed, 3);
    expect(result.parsed, 1);
    expect(result.unparsed, 1);
    expect(result.errors, 1);
    expect(await database.select(database.transactions).get(), hasLength(1));

    final rows = await database.select(database.shadowTransactions).get();
    expect(rows, hasLength(3));
    expect(
      rows.singleWhere((row) => row.sourceId == 'sms_parsed').amountPaise,
      44900,
    );
    expect(
      rows.singleWhere((row) => row.sourceId == 'sms_error').outcome,
      'error',
    );

    await runner.run([_sms('sms_parsed')]);
    expect(
      await database.select(database.shadowTransactions).get(),
      hasLength(3),
    );
  });
}

RawSms _sms(String id) => RawSms(
      id: id,
      sender: 'VK-TEST',
      body: 'sanitized test body',
      receivedAt: DateTime.utc(2026, 8, 7),
    );
