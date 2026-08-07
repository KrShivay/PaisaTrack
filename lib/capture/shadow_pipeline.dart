import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../data/models/raw_sms.dart';

enum ShadowOutcome {
  parsed('parsed'),
  unparsed('unparsed'),
  error('error');

  const ShadowOutcome(this.wireName);

  final String wireName;
}

/// Normalized, privacy-safe output from one shadow evaluation.
class ShadowObservation {
  const ShadowObservation({
    required this.sourceId,
    required this.pipelineVersion,
    required this.outcome,
    this.amountPaise,
    this.direction,
    this.merchantKey,
    this.categoryId,
  });

  final String sourceId;
  final String pipelineVersion;
  final ShadowOutcome outcome;
  final int? amountPaise;
  final String? direction;
  final String? merchantKey;
  final String? categoryId;
}

typedef ShadowEvaluator = Future<ShadowObservation> Function(RawSms message);

class ShadowRunResult {
  const ShadowRunResult({
    required this.processed,
    required this.parsed,
    required this.unparsed,
    required this.errors,
  });

  final int processed;
  final int parsed;
  final int unparsed;
  final int errors;
}

/// Runs a candidate pipeline into shadow storage without touching production
/// transaction rows. Scheduling and comparison are separate follow-up slices.
class ShadowPipelineRunner {
  ShadowPipelineRunner(
    this._database, {
    required ShadowEvaluator evaluate,
    DateTime Function()? now,
  })  : _evaluate = evaluate,
        _now = now ?? DateTime.now;

  final AppDatabase _database;
  final ShadowEvaluator _evaluate;
  final DateTime Function() _now;

  Future<ShadowRunResult> run(Iterable<RawSms> messages) async {
    final observations = <ShadowObservation>[];
    for (final message in messages) {
      try {
        observations.add(await _evaluate(message));
      } on Object {
        observations.add(
          ShadowObservation(
            sourceId: message.id,
            pipelineVersion: 'unknown',
            outcome: ShadowOutcome.error,
          ),
        );
      }
    }

    final observedAt = _now().toUtc();
    await _database.transaction(() async {
      for (final observation in observations) {
        await _database
            .into(_database.shadowTransactions)
            .insertOnConflictUpdate(
              ShadowTransactionsCompanion.insert(
                id: '${observation.pipelineVersion}:${observation.sourceId}',
                sourceId: observation.sourceId,
                pipelineVersion: observation.pipelineVersion,
                outcome: observation.outcome.wireName,
                amountPaise: Value(observation.amountPaise),
                direction: Value(observation.direction),
                merchantKey: Value(observation.merchantKey),
                categoryId: Value(observation.categoryId),
                observedAt: observedAt,
                updatedAt: observedAt,
              ),
            );
      }
    });

    return ShadowRunResult(
      processed: observations.length,
      parsed: observations
          .where((observation) => observation.outcome == ShadowOutcome.parsed)
          .length,
      unparsed: observations
          .where((observation) => observation.outcome == ShadowOutcome.unparsed)
          .length,
      errors: observations
          .where((observation) => observation.outcome == ShadowOutcome.error)
          .length,
    );
  }
}
