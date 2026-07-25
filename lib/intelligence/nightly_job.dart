import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../core/crypto/database_cipher.dart';
import '../data/db/database.dart';
import '../data/db/database_provider.dart';
import '../enrichment/decision_policy.dart';
import '../enrichment/local_classifier.dart';
import 'anomaly_detector.dart';
import 'burn_rate_forecaster.dart';
import 'insights_engine.dart';
import 'llm/llm_runtime.dart';
import 'narrative_insight_generator.dart';
import 'recurring_detector.dart';

const nightlyWorkName = 'paisatrack-nightly-intelligence';
const nightlyTaskName = 'nightly-intelligence-v1';
const _checkpointKey = 'nightly_pipeline_checkpoint_v1';

typedef NightlyStageAction = Future<void> Function(DateTime now);

enum NightlyStage {
  purgeExpiredRawSms,
  recurringScan,
  baselines,
  retrainClassifier,
  recomputeThresholds,
  precomputeInsights,
}

class NightlyRunResult {
  const NightlyRunResult({
    required this.completed,
    required this.stagesRun,
  });

  final bool completed;
  final List<NightlyStage> stagesRun;
}

/// Checkpointed implementation of PLAN §7.9's nightly intelligence pipeline.
class NightlyPipeline {
  NightlyPipeline({
    required AppDatabase database,
    required Map<NightlyStage, NightlyStageAction> actions,
    this.timeLimit = const Duration(minutes: 3),
    DateTime Function()? clock,
  })  : _database = database,
        _actions = actions,
        _clock = clock ?? DateTime.now;

  factory NightlyPipeline.production(AppDatabase database) {
    return NightlyPipeline(
      database: database,
      actions: {
        NightlyStage.purgeExpiredRawSms: (now) async {
          await database.transaction(() async {
            final expiredIds = database.selectOnly(database.rawSms)
              ..addColumns([database.rawSms.id])
              ..where(
                database.rawSms.purgeAfter.isSmallerOrEqualValue(now),
              );
            // Transactions are permanent; raw bodies are not. Detach the
            // nullable provenance link before deleting expired raw rows so
            // full-history imports do not defeat the privacy retention rule.
            await (database.update(database.transactions)
                  ..where((row) => row.smsId.isInQuery(expiredIds)))
                .write(
              const TransactionsCompanion(smsId: Value(null)),
            );
            await (database.delete(database.rawSms)
                  ..where((row) => row.purgeAfter.isSmallerOrEqualValue(now)))
                .go();
          });
        },
        NightlyStage.recurringScan: (now) async {
          await RecurringDetector(database).run(today: now);
        },
        NightlyStage.baselines: (now) async {
          await AnomalyDetector(database).run(today: now);
        },
        NightlyStage.retrainClassifier: (_) async {
          await ClassifierTrainer(database).train(minimumNewFeedback: 30);
        },
        NightlyStage.recomputeThresholds: (_) async {
          await AdaptiveThresholdPolicy(database).recompute();
        },
        NightlyStage.precomputeInsights: (now) async {
          await BurnRateForecaster(database).run(today: now);
          await InsightsEngine(database).run(today: now);
          await NarrativeInsightGenerator(
            database,
            const PlatformLlmRuntime(),
          ).run(today: now);
        },
      },
    );
  }

  final AppDatabase _database;
  final Map<NightlyStage, NightlyStageAction> _actions;
  final Duration timeLimit;
  final DateTime Function() _clock;

  Future<NightlyRunResult> run({DateTime? now}) => runStages(now: now);

  Future<NightlyRunResult> runStages({
    Set<NightlyStage>? only,
    DateTime? now,
  }) async {
    final startedAt = _clock();
    final runAt = (now ?? startedAt).toUtc();
    final runDay = _dayKey(runAt);
    final checkpoint = await _readCheckpoint();
    var nextIndex = checkpoint.$1 == runDay ? checkpoint.$2 : 0;
    final stagesRun = <NightlyStage>[];

    while (nextIndex < NightlyStage.values.length) {
      final stage = NightlyStage.values[nextIndex];
      if (only != null && !only.contains(stage)) {
        nextIndex++;
        continue;
      }
      final remaining = timeLimit - _clock().difference(startedAt);
      if (remaining <= Duration.zero) {
        return NightlyRunResult(completed: false, stagesRun: stagesRun);
      }
      final action = _actions[stage];
      if (action == null) {
        throw StateError('Missing nightly action for ${stage.name}');
      }
      try {
        await action(runAt).timeout(remaining);
      } on TimeoutException {
        return NightlyRunResult(completed: false, stagesRun: stagesRun);
      }
      stagesRun.add(stage);
      nextIndex++;
      await _writeCheckpoint(runDay, nextIndex);
    }
    return NightlyRunResult(completed: true, stagesRun: stagesRun);
  }

  Future<(String?, int)> _readCheckpoint() async {
    final row = await (_database.select(_database.modelMeta)
          ..where((entry) => entry.key.equals(_checkpointKey)))
        .getSingleOrNull();
    if (row == null) return (null, 0);
    try {
      final json = jsonDecode(row.value) as Map<String, Object?>;
      return (json['day'] as String?, json['next_stage'] as int? ?? 0);
    } on FormatException {
      return (null, 0);
    } on TypeError {
      return (null, 0);
    }
  }

  Future<void> _writeCheckpoint(String day, int nextStage) {
    return _database.into(_database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: _checkpointKey,
            value: jsonEncode({'day': day, 'next_stage': nextStage}),
          ),
        );
  }

  String _dayKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

@pragma('vm:entry-point')
void nightlyCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != nightlyTaskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final database = await _openWorkerDatabase();
    try {
      final result = await NightlyPipeline.production(database).run();
      return result.completed;
    } finally {
      await closeAppDatabase(database);
    }
  });
}

Future<void> initializeNightlyWork() async {
  await Workmanager().initialize(nightlyCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    nightlyWorkName,
    nightlyTaskName,
    frequency: const Duration(hours: 24),
    // `keep` preserves constraints from an older install. `update` is needed
    // so devices already holding the charging+idle job receive this fix.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(
      requiresBatteryNotLow: true,
    ),
  );
}

Future<AppDatabase> _openWorkerDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  final passphrase =
      await AndroidKeystoreDatabasePassphraseProvider().getPassphrase();
  return AppDatabase(
    openEncryptedDatabase(
      file: File(p.join(directory.path, appDatabaseFileName)),
      passphrase: passphrase,
    ),
  );
}
