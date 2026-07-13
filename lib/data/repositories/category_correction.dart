enum CorrectionScope {
  thisTransaction,
  futureMatching,
  existingAndFuture,
  matchingGroup,
  updateFutureRule,
}

enum CorrectionContext {
  oneOffEdit,
  newMerchant,
  groupReview,
  historicalCleanup,
  existingRule,
}

CorrectionScope defaultCorrectionScope(CorrectionContext context) {
  return switch (context) {
    CorrectionContext.oneOffEdit => CorrectionScope.thisTransaction,
    CorrectionContext.newMerchant => CorrectionScope.futureMatching,
    CorrectionContext.groupReview => CorrectionScope.matchingGroup,
    CorrectionContext.historicalCleanup => CorrectionScope.existingAndFuture,
    CorrectionContext.existingRule => CorrectionScope.updateFutureRule,
  };
}

extension CorrectionScopeBehavior on CorrectionScope {
  bool get createsRule => switch (this) {
        CorrectionScope.futureMatching ||
        CorrectionScope.existingAndFuture ||
        CorrectionScope.updateFutureRule =>
          true,
        CorrectionScope.thisTransaction ||
        CorrectionScope.matchingGroup =>
          false,
      };

  bool get updatesExisting => switch (this) {
        CorrectionScope.existingAndFuture ||
        CorrectionScope.matchingGroup =>
          true,
        _ => false,
      };
}

class CategoryCorrectionResult {
  const CategoryCorrectionResult({
    required this.feedbackCount,
    required this.affectedTransactionCount,
    required this.ruleCreated,
  });

  final int feedbackCount;
  final int affectedTransactionCount;
  final bool ruleCreated;
}
