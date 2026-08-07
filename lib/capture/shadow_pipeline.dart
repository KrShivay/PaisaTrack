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

class ShadowSnapshot {
  const ShadowSnapshot({
    required this.sourceId,
    required this.outcome,
    this.amountPaise,
    this.direction,
    this.merchantKey,
    this.categoryId,
    this.updatedAt,
  });

  final String sourceId;
  final ShadowOutcome outcome;
  final int? amountPaise;
  final String? direction;
  final String? merchantKey;
  final String? categoryId;
  final DateTime? updatedAt;
}

class ProductionSnapshot {
  const ProductionSnapshot({
    required this.sourceId,
    required this.amountPaise,
    required this.direction,
    this.merchantKey,
    this.categoryId,
  });

  final String sourceId;
  final int amountPaise;
  final String direction;
  final String? merchantKey;
  final String? categoryId;
}

enum ShadowDifferenceKind { gained, lost, amountDelta, labelDisagreement }

class ShadowDifference {
  const ShadowDifference({required this.sourceId, required this.kinds});

  final String sourceId;
  final Set<ShadowDifferenceKind> kinds;
}

class ShadowDiff {
  const ShadowDiff(this.differences);

  final List<ShadowDifference> differences;

  int get gained => _count(ShadowDifferenceKind.gained);
  int get lost => _count(ShadowDifferenceKind.lost);
  int get amountDeltas => _count(ShadowDifferenceKind.amountDelta);
  int get labelDisagreements => _count(ShadowDifferenceKind.labelDisagreement);
  bool get isEmpty => differences.isEmpty;

  int _count(ShadowDifferenceKind kind) =>
      differences.where((difference) => difference.kinds.contains(kind)).length;
}

/// Compares one shadow result per source with the current production snapshot.
///
/// The comparator is pure: callers can load rows from Drift, but no database
/// writes or current-pipeline assumptions are hidden in the calculation.
class ShadowDiffCalculator {
  const ShadowDiffCalculator();

  ShadowDiff compare({
    required Iterable<ShadowSnapshot> shadow,
    required Iterable<ProductionSnapshot> production,
  }) {
    final shadowBySource = <String, ShadowSnapshot>{};
    for (final row in shadow) {
      final prior = shadowBySource[row.sourceId];
      if (prior == null ||
          (row.updatedAt != null &&
              (prior.updatedAt == null ||
                  row.updatedAt!.isAfter(prior.updatedAt!)))) {
        shadowBySource[row.sourceId] = row;
      }
    }
    final productionBySource = {
      for (final row in production) row.sourceId: row,
    };
    final sourceIds = {
      ...shadowBySource.keys,
      ...productionBySource.keys,
    }.toList()
      ..sort();
    final differences = <ShadowDifference>[];
    for (final sourceId in sourceIds) {
      final shadowRow = shadowBySource[sourceId];
      final productionRow = productionBySource[sourceId];
      final kinds = <ShadowDifferenceKind>{};
      if (shadowRow?.outcome == ShadowOutcome.parsed && productionRow == null) {
        kinds.add(ShadowDifferenceKind.gained);
      }
      if (productionRow != null && shadowRow?.outcome != ShadowOutcome.parsed) {
        kinds.add(ShadowDifferenceKind.lost);
      }
      if (shadowRow?.outcome == ShadowOutcome.parsed && productionRow != null) {
        if (shadowRow!.amountPaise != productionRow.amountPaise) {
          kinds.add(ShadowDifferenceKind.amountDelta);
        }
        if (shadowRow.direction != productionRow.direction ||
            shadowRow.merchantKey != productionRow.merchantKey ||
            shadowRow.categoryId != productionRow.categoryId) {
          kinds.add(ShadowDifferenceKind.labelDisagreement);
        }
      }
      if (kinds.isNotEmpty) {
        differences.add(
          ShadowDifference(sourceId: sourceId, kinds: Set.unmodifiable(kinds)),
        );
      }
    }
    return ShadowDiff(List.unmodifiable(differences));
  }
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
