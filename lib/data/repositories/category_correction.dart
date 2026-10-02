import 'rule_repository.dart';

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
    this.ruleMutation,
    this.affectedTransactions = const [],
  });

  final int feedbackCount;
  final int affectedTransactionCount;
  final bool ruleCreated;
  final RuleMutation? ruleMutation;
  final List<CorrectedTransactionSnapshot> affectedTransactions;
}

class CorrectedTransactionSnapshot {
  const CorrectedTransactionSnapshot({
    required this.id,
    required this.categoryId,
    required this.status,
    required this.feedbackIds,
  });

  final String id;
  final String? categoryId;
  final String status;
  final List<String> feedbackIds;
}
