/// Privacy-safe summary contract for a chronological capture evaluation.
///
/// This is test tooling: it accepts normalized decisions and independently
/// sourced labels, never raw SMS text or automatic transaction status as truth.
enum CaptureLabelSource { confirmed, corrected, unreviewed, absent }

class CaptureReplayObservation {
  const CaptureReplayObservation({
    required this.smsId,
    required this.receivedAt,
    required this.predictedCategoryId,
    required this.labelSource,
    this.explicitCategoryId,
    this.sourceEvidenceAvailable = true,
    this.decisionVersion,
  }) : assert(
          (labelSource == CaptureLabelSource.confirmed ||
                  labelSource == CaptureLabelSource.corrected)
              ? explicitCategoryId != null
              : explicitCategoryId == null,
        );

  final String smsId;
  final DateTime receivedAt;
  final String? predictedCategoryId;
  final String? explicitCategoryId;
  final CaptureLabelSource labelSource;
  final bool sourceEvidenceAvailable;
  final String? decisionVersion;

  bool get hasExplicitLabel =>
      labelSource == CaptureLabelSource.confirmed ||
      labelSource == CaptureLabelSource.corrected;
}

class CaptureReplayReport {
  CaptureReplayReport._({
    required this.chronologicalIds,
    required this.cohorts,
    required this.totalRows,
    required this.explicitLabelRows,
    required this.predictedRows,
    required this.evaluatedRows,
    required this.correctRows,
    required this.incorrectRows,
    required this.abstainedLabelRows,
    required this.unreviewedRowsExcluded,
    required this.unlabeledRows,
    required this.missingSourceEvidenceRows,
    required this.missingDecisionVersionRows,
    required this.userDecisionsPer100Rows,
    required this.decisionCoverage,
    required this.explicitLabelCoverage,
    required this.measuredPrecision,
  });

  factory CaptureReplayReport.fromObservations(
    Iterable<CaptureReplayObservation> observations,
  ) {
    final rows = observations.toList()
      ..sort((a, b) {
        final byTime = a.receivedAt.toUtc().compareTo(b.receivedAt.toUtc());
        return byTime != 0 ? byTime : a.smsId.compareTo(b.smsId);
      });
    final seenIds = <String>{};
    for (final row in rows) {
      if (!seenIds.add(row.smsId)) {
        throw ArgumentError.value(row.smsId, 'smsId', 'must be unique');
      }
    }

    final labeled = rows.where((row) => row.hasExplicitLabel).toList();
    final evaluated =
        labeled.where((row) => row.predictedCategoryId != null).toList();
    final correct = evaluated
        .where((row) => row.predictedCategoryId == row.explicitCategoryId)
        .length;
    final predicted = rows.where((row) => row.predictedCategoryId != null);
    final decisionVersions = rows.where((row) => row.decisionVersion != null);

    final byMonth = <String, List<CaptureReplayObservation>>{};
    for (final row in rows) {
      final time = row.receivedAt.toUtc();
      final key = '${time.year.toString().padLeft(4, '0')}-'
          '${time.month.toString().padLeft(2, '0')}';
      byMonth.putIfAbsent(key, () => []).add(row);
    }
    final cohorts = byMonth.entries.map((entry) {
      final cohortRows = entry.value;
      final cohortLabeled = cohortRows.where((row) => row.hasExplicitLabel);
      final cohortEvaluated = cohortLabeled
          .where((row) => row.predictedCategoryId != null)
          .toList();
      final cohortCorrect = cohortEvaluated
          .where((row) => row.predictedCategoryId == row.explicitCategoryId)
          .length;
      return CaptureReplayCohort(
        monthUtc: entry.key,
        rowCount: cohortRows.length,
        explicitLabelCount: cohortLabeled.length,
        evaluatedCount: cohortEvaluated.length,
        correctCount: cohortCorrect,
        incorrectCount: cohortEvaluated.length - cohortCorrect,
        precision: cohortEvaluated.isEmpty
            ? null
            : cohortCorrect / cohortEvaluated.length,
      );
    }).toList(growable: false);

    return CaptureReplayReport._(
      chronologicalIds: List.unmodifiable(rows.map((row) => row.smsId)),
      cohorts: List.unmodifiable(cohorts),
      totalRows: rows.length,
      explicitLabelRows: labeled.length,
      predictedRows: predicted.length,
      evaluatedRows: evaluated.length,
      correctRows: correct,
      incorrectRows: evaluated.length - correct,
      abstainedLabelRows: labeled.length - evaluated.length,
      unreviewedRowsExcluded: rows
          .where((row) => row.labelSource == CaptureLabelSource.unreviewed)
          .length,
      unlabeledRows: rows
          .where((row) => row.labelSource == CaptureLabelSource.absent)
          .length,
      missingSourceEvidenceRows:
          rows.where((row) => !row.sourceEvidenceAvailable).length,
      missingDecisionVersionRows: rows.length - decisionVersions.length,
      userDecisionsPer100Rows:
          rows.isEmpty ? null : labeled.length * 100 / rows.length,
      decisionCoverage: rows.isEmpty ? null : predicted.length / rows.length,
      explicitLabelCoverage:
          labeled.isEmpty ? null : evaluated.length / labeled.length,
      measuredPrecision: evaluated.isEmpty ? null : correct / evaluated.length,
    );
  }

  final List<String> chronologicalIds;
  final List<CaptureReplayCohort> cohorts;
  final int totalRows;
  final int explicitLabelRows;
  final int predictedRows;
  final int evaluatedRows;
  final int correctRows;
  final int incorrectRows;
  final int abstainedLabelRows;
  final int unreviewedRowsExcluded;
  final int unlabeledRows;
  final int missingSourceEvidenceRows;
  final int missingDecisionVersionRows;
  final double? userDecisionsPer100Rows;
  final double? decisionCoverage;
  final double? explicitLabelCoverage;
  final double? measuredPrecision;

  int get precisionNumerator => correctRows;
  int get precisionDenominator => evaluatedRows;
  int get coverageNumerator => predictedRows;
  int get coverageDenominator => totalRows;
  int get explicitLabelCoverageNumerator => evaluatedRows;
  int get explicitLabelCoverageDenominator => explicitLabelRows;

  String get evaluationScope => 'observed_explicit_feedback';

  /// Explicit labels describe only the observed sample; this report never
  /// presents it as a chronological holdout or validated rollout baseline.
  bool get isHoldoutValidated => false;

  bool get evidenceComplete =>
      totalRows > 0 &&
      explicitLabelRows == totalRows &&
      missingSourceEvidenceRows == 0 &&
      missingDecisionVersionRows == 0;
}

class CaptureReplayCohort {
  const CaptureReplayCohort({
    required this.monthUtc,
    required this.rowCount,
    required this.explicitLabelCount,
    required this.evaluatedCount,
    required this.correctCount,
    required this.incorrectCount,
    required this.precision,
  });

  final String monthUtc;
  final int rowCount;
  final int explicitLabelCount;
  final int evaluatedCount;
  final int correctCount;
  final int incorrectCount;
  final double? precision;
}
