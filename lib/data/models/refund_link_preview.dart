import 'source_currency.dart';

/// Outcome of a read-only preview over a persisted refund credit.
enum RefundLinkPreviewStatus {
  ready,
  noMatch,
  ambiguous,
  blocked,
  missingRefund,
}

/// Why a preview cannot recommend one compatible purchase.
enum RefundLinkPreviewBlockReason {
  invalidRefund,
  missingExactReference,
  alreadyLinked,
  overCap,
  invalidExistingLinks,
  unsupportedAmountPrecision,
  lookupLimitExceeded,
}

/// Pair arithmetic for one exact-reference purchase candidate.
///
/// Amounts remain in the source table's represented unit. They are not
/// assigned to a month and do not constitute a net-spend total.
class RefundLinkPreviewCandidate {
  const RefundLinkPreviewCandidate({
    required this.originalTransactionId,
    required this.originalDate,
    required this.originalGrossAmount,
    required this.existingAdjustmentAmount,
    required this.proposedRefundAmount,
    required this.remainingRefundableAmount,
  });

  final String originalTransactionId;
  final DateTime originalDate;
  final double originalGrossAmount;
  final double existingAdjustmentAmount;
  final double proposedRefundAmount;
  final double remainingRefundableAmount;
}

/// Read-only result for reviewing a possible refund-to-purchase relationship.
class RefundLinkPreview {
  RefundLinkPreview({
    required this.refundTransactionId,
    required this.status,
    this.refundDate,
    this.refundAmount,
    this.currency,
    required List<RefundLinkPreviewCandidate> candidates,
    this.blockReason,
  }) : candidates = List.unmodifiable(candidates);

  final String refundTransactionId;
  final RefundLinkPreviewStatus status;
  final DateTime? refundDate;
  final double? refundAmount;
  final SourceCurrency? currency;
  final List<RefundLinkPreviewCandidate> candidates;
  final RefundLinkPreviewBlockReason? blockReason;
}
