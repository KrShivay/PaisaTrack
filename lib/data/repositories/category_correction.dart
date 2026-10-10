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
    this.postCategoryId,
    this.postStatus = 'confirmed',
    this.baselineFeedback = const [],
    this.receiptFeedback = const [],
    this.descriptionChanged = false,
    this.descriptionBefore,
    this.descriptionAfter,
    this.merchantId,
    this.merchantRaw,
    this.counterpartyVpa,
    this.parseSource = 'unknown',
    this.smsId,
    this.paymentSourceId,
    this.channel = 'unknown',
    this.accountHint,
    this.direction = 'unknown',
    this.amount = 0,
    this.ts = 0,
    this.currencyCode,
    this.currencySymbol,
    this.lifecycleState = 'unknown',
    this.lifecycleReason,
    this.messageKind,
    this.confidenceJson = '{}',
    this.evidenceJson,
    this.refId,
    this.ownedTransferId,
    this.isAnalyticsExcluded = false,
    this.isDeleted = false,
    this.isNotTransaction = false,
    this.duplicateOfTxnId,
    this.hasUndoGuardEvidence = false,
  });

  final String id;
  final String? categoryId;
  final String status;
  final String? postCategoryId;
  final String postStatus;
  final List<String> feedbackIds;
  final List<CorrectionFeedbackSnapshot> baselineFeedback;
  final List<CorrectionFeedbackSnapshot> receiptFeedback;
  final bool descriptionChanged;
  final String? descriptionBefore;
  final String? descriptionAfter;
  final String? merchantId;
  final String? merchantRaw;
  final String? counterpartyVpa;
  final String parseSource;
  final String? smsId;
  final String? paymentSourceId;
  final String channel;
  final String? accountHint;
  final String direction;
  final double amount;
  final int ts;
  final String? currencyCode;
  final String? currencySymbol;
  final String lifecycleState;
  final String? lifecycleReason;
  final String? messageKind;
  final String confidenceJson;
  final String? evidenceJson;
  final String? refId;
  final String? ownedTransferId;
  final bool isAnalyticsExcluded;
  final bool isDeleted;
  final bool isNotTransaction;
  final String? duplicateOfTxnId;
  final bool hasUndoGuardEvidence;
}

/// Ephemeral exact feedback row evidence owned by one correction receipt.
/// This stays in memory with the undo token; no database metadata is added.
class CorrectionFeedbackSnapshot {
  const CorrectionFeedbackSnapshot({
    required this.id,
    required this.txnId,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.context,
    required this.modelConfidenceAtTime,
    required this.createdAt,
  });

  final String id;
  final String txnId;
  final String field;
  final String? oldValue;
  final String? newValue;
  final String context;
  final double? modelConfidenceAtTime;
  final DateTime createdAt;
}
