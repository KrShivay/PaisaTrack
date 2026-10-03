import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/nightly_job.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('seeded DB run executes every stage in PLAN order', () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'expired',
            sender: 'BANK',
            body: 'old',
            receivedAt: DateTime.utc(2025),
            parserVersion: const Value(1),
            failureReason: const Value('processing_error'),
            purgeAfter: DateTime.utc(2025, 1, 31),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_expired',
            ts: DateTime.utc(2025).millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            smsId: const Value('expired'),
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: DateTime.utc(2025),
            updatedAt: DateTime.utc(2025),
          ),
        );
    final pipeline = NightlyPipeline.production(database);

    final result = await pipeline.run(now: DateTime.utc(2026, 7, 12));

    expect(result.completed, isTrue);
    expect(result.stagesRun, NightlyStage.values);
    // ADR 0021: the source SMS of a transaction is provenance, kept forever.
    expect(
      (await database.select(database.rawSms).get()).map((row) => row.id),
      ['expired'],
    );
    final transaction =
        await database.select(database.transactions).getSingle();
    expect(transaction.id, 'txn_expired');
    expect(transaction.smsId, 'expired');
  });

  test('purge keeps linked SMS and removes unlinked SMS after 7 days',
      () async {
    final now = DateTime.utc(2026, 10, 3, 12);
    Future<void> insertSms(
      String id, {
      required DateTime receivedAt,
      required DateTime purgeAfter,
    }) =>
        database.into(database.rawSms).insert(
              RawSmsCompanion.insert(
                id: id,
                sender: 'VK-HDFCBK',
                body: 'Synthetic body $id',
                receivedAt: receivedAt,
                purgeAfter: purgeAfter,
              ),
            );
    final old = now.subtract(const Duration(days: 400));
    await insertSms('txn_sms', receivedAt: old, purgeAfter: old);
    await insertSms('disposition_sms', receivedAt: old, purgeAfter: old);
    // Captured before ADR 0021 with the old 30-day deadline still ahead.
    await insertSms(
      'legacy_unlinked',
      receivedAt: now.subtract(const Duration(days: 8)),
      purgeAfter: now.add(const Duration(days: 22)),
    );
    await insertSms(
      'fresh_unlinked',
      receivedAt: now.subtract(const Duration(days: 6)),
      purgeAfter: now.add(const Duration(days: 1)),
    );
    await insertSms(
      'expired_unlinked',
      receivedAt: now.subtract(const Duration(days: 7)),
      purgeAfter: now,
    );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn',
            ts: old.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            smsId: const Value('txn_sms'),
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: old,
            updatedAt: old,
          ),
        );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'disposition_sms',
            transactionId: 'txn_deleted',
            disposition: 'not_transaction',
            createdAt: old,
          ),
        );

    await NightlyPipeline.production(database).runStages(
      only: {NightlyStage.purgeExpiredRawSms},
      now: now,
    );

    final kept = (await database.select(database.rawSms).get())
        .map((row) => row.id)
        .toSet();
    expect(kept, {'txn_sms', 'disposition_sms', 'fresh_unlinked'});
    final transaction =
        await database.select(database.transactions).getSingle();
    expect(transaction.smsId, 'txn_sms');
  });

  test('failed run resumes after the last completed stage', () async {
    final calls = <NightlyStage>[];
    var failOnce = true;
    Map<NightlyStage, NightlyStageAction> actions() => {
          for (final stage in NightlyStage.values)
            stage: (_) async {
              calls.add(stage);
              if (stage == NightlyStage.baselines && failOnce) {
                failOnce = false;
                throw StateError('simulated interruption');
              }
            },
        };
    final pipeline = NightlyPipeline(database: database, actions: actions());

    await expectLater(
      pipeline.run(now: DateTime.utc(2026, 7, 12)),
      throwsStateError,
    );
    final resumed = await NightlyPipeline(
      database: database,
      actions: actions(),
    ).run(now: DateTime.utc(2026, 7, 12));

    expect(resumed.completed, isTrue);
    expect(
      calls,
      [
        NightlyStage.purgeExpiredRawSms,
        NightlyStage.recurringScan,
        NightlyStage.baselines,
        NightlyStage.baselines,
        NightlyStage.retrainClassifier,
        NightlyStage.recomputeThresholds,
        NightlyStage.merchantClustering,
        NightlyStage.precomputeInsights,
      ],
    );
  });

  test('completed run is idempotent for the same UTC day', () async {
    var calls = 0;
    final pipeline = NightlyPipeline(
      database: database,
      actions: {
        for (final stage in NightlyStage.values) stage: (_) async => calls++,
      },
    );
    final day = DateTime.utc(2026, 7, 12);

    await pipeline.run(now: day);
    final second = await pipeline.run(now: day);

    expect(second.completed, isTrue);
    expect(second.stagesRun, isEmpty);
    expect(calls, NightlyStage.values.length);
  });

  test('checkpoint day uses the shared clock and financial calendar', () async {
    final pipeline = NightlyPipeline(
      database: database,
      actions: {
        for (final stage in NightlyStage.values) stage: (_) async {},
      },
      clock: () => DateTime.utc(2026, 7, 11, 19),
      calendar: const FinancialCalendar.fixed(Duration(hours: 5, minutes: 30)),
    );

    await pipeline.run();

    final checkpoint = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals('nightly_pipeline_checkpoint_v1')))
        .getSingle();
    expect(jsonDecode(checkpoint.value), {
      'day': '2026-07-12',
      'next_stage': NightlyStage.values.length,
    });
  });
}
