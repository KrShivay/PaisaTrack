import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(await database.select(database.rawSms).get(), isEmpty);
    final transaction =
        await database.select(database.transactions).getSingle();
    expect(transaction.id, 'txn_expired');
    expect(transaction.smsId, isNull);
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
}
