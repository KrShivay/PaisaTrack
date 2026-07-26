import '../data/db/database.dart';
import '../data/models/normalized_transaction_record.dart';

/// Link type for graph connections between correlated transactions.
enum TransactionLinkType {
  echo('echo'),
  settles('settles'),
  reverses('reverses'),
  refunds('refunds'),
  repays('repays'),
  transferLeg('transfer_leg'),
  fulfills('fulfills');

  const TransactionLinkType(this.wireName);
  final String wireName;
}

/// Result of evaluating the correlation key ladder for a transaction.
class EventCorrelationResult {
  const EventCorrelationResult({
    required this.matchedTransactionId,
    required this.linkType,
    required this.basis,
    this.confidence = 1.0,
    this.eventId,
  });

  final String matchedTransactionId;
  final TransactionLinkType linkType;
  final String basis;
  final double confidence;
  final String? eventId;
}

/// Correlates new transactions into existing financial events and transaction links
/// using an ordered correlation key ladder.
class EventCorrelator {
  const EventCorrelator();

  /// Normalizes a reference/UTR string to the longest digit run >= 9 or exact string >= 6 chars.
  static String? normalizeRefId(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final trimmed = ref.trim();
    if (trimmed.length < 6) return null;

    final digitRuns = RegExp(r'\d{9,}').allMatches(trimmed);
    if (digitRuns.isNotEmpty) {
      var longest = '';
      for (final match in digitRuns) {
        final run = match.group(0)!;
        if (run.length > longest.length) {
          longest = run;
        }
      }
      return longest;
    }
    return trimmed.toUpperCase();
  }

  /// Returns true if both transactions have non-null normalized ref IDs that differ.
  static bool hasRefDisagreement(String? refA, String? refB) {
    final normA = normalizeRefId(refA);
    final normB = normalizeRefId(refB);
    if (normA != null && normB != null && normA != normB) {
      return true;
    }
    return false;
  }

  /// Evaluates candidates against [record] using the ordered correlation ladder.
  /// First tier to match wins; ref disagreement vetoes candidate pairing.
  EventCorrelationResult? correlate({
    required NormalizedTransactionRecord record,
    required List<Transaction> candidates,
  }) {
    final normRef = normalizeRefId(record.refId);

    // Tier 1: UTR / Ref match within +/- 30 days
    if (normRef != null) {
      for (final candidate in candidates) {
        final candNormRef = normalizeRefId(candidate.refId);
        if (candNormRef == normRef) {
          final diffMs = (record.ts.millisecondsSinceEpoch - candidate.ts).abs();
          if (diffMs <= const Duration(days: 30).inMilliseconds) {
            final linkType = record.direction.wireName != candidate.direction
                ? TransactionLinkType.reverses
                : TransactionLinkType.echo;
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: linkType,
              basis: 'ref_match:$normRef',
              confidence: 0.99,
            );
          }
        }
      }
    }

    // Tier 2: Auth vs Settle match within +/- 5 days (card_last4|merchant|amount +/- 2%)
    final recordAccount = record.accountHint?.toUpperCase();
    final recordMerchant = record.merchantRaw?.toUpperCase();
    for (final candidate in candidates) {
      if (hasRefDisagreement(record.refId, candidate.refId)) continue;

      final diffMs = (record.ts.millisecondsSinceEpoch - candidate.ts).abs();
      if (diffMs <= const Duration(days: 5).inMilliseconds) {
        final amountRatio = candidate.amount == 0 ? 0.0 : (record.amount - candidate.amount).abs() / candidate.amount;
        if (amountRatio <= 0.02) {
          final candAccount = candidate.accountHint?.toUpperCase();
          final candMerchant = candidate.merchantRaw?.toUpperCase();

          final accountMatch = recordAccount != null && candAccount != null && recordAccount == candAccount;
          final merchantMatch = recordMerchant != null && candMerchant != null && (recordMerchant == candMerchant || recordMerchant.startsWith('$candMerchant '));

          if (accountMatch || merchantMatch) {
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: TransactionLinkType.settles,
              basis: 'auth_settle_match',
              confidence: 0.95,
            );
          }
        }
      }
    }

    // Tier 3: Reversal match within +/- 30 days (opposite direction, matching amount)
    for (final candidate in candidates) {
      if (hasRefDisagreement(record.refId, candidate.refId)) continue;

      if (record.direction.wireName != candidate.direction) {
        final diffMs = (record.ts.millisecondsSinceEpoch - candidate.ts).abs();
        if (diffMs <= const Duration(days: 30).inMilliseconds) {
          if ((record.amount - candidate.amount).abs() <= 0.01) {
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: TransactionLinkType.reverses,
              basis: 'reversal_amount_match',
              confidence: 0.90,
            );
          }
        }
      }
    }

    // Tier 4: Echo match within +/- 10 minutes (existing semantics, same direction & amount)
    for (final candidate in candidates) {
      if (hasRefDisagreement(record.refId, candidate.refId)) continue;

      if (record.direction.wireName == candidate.direction) {
        final diffMs = (record.ts.millisecondsSinceEpoch - candidate.ts).abs();
        if (diffMs <= const Duration(minutes: 10).inMilliseconds) {
          if ((record.amount - candidate.amount).abs() <= 0.01) {
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: TransactionLinkType.echo,
              basis: 'echo_time_amount_match',
              confidence: 0.98,
            );
          }
        }
      }
    }

    // Tier 5: Transfer leg match within +/- 60 minutes between owned payment sources
    for (final candidate in candidates) {
      if (hasRefDisagreement(record.refId, candidate.refId)) continue;

      if (record.direction.wireName != candidate.direction && candidate.paymentSourceId != null) {
        final diffMs = (record.ts.millisecondsSinceEpoch - candidate.ts).abs();
        if (diffMs <= const Duration(minutes: 60).inMilliseconds) {
          if ((record.amount - candidate.amount).abs() <= 0.01) {
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: TransactionLinkType.transferLeg,
              basis: 'transfer_owned_sources',
              confidence: 0.92,
            );
          }
        }
      }
    }

    return null;
  }

  /// Evaluates refund correlation against expense [candidates].
  ///
  /// Auto-links at confidence >= 0.90:
  /// - Exact ref ID match within 30 days (confidence 0.99)
  /// - Exact/partial amount + same counterparty within 30 days with single candidate (confidence >= 0.91)
  ///
  /// Ambiguous cases (multiple candidates) return null (fail closed, unlinked).
  EventCorrelationResult? correlateRefund({
    required NormalizedTransactionRecord refundRecord,
    required List<Transaction> candidates,
  }) {
    final normRef = normalizeRefId(refundRecord.refId);

    // Tier 1: Exact UTR / Ref match within 30 days
    if (normRef != null) {
      for (final candidate in candidates) {
        if (candidate.direction != 'debit') continue;
        final candNormRef = normalizeRefId(candidate.refId);
        if (candNormRef == normRef) {
          final diffMs = (refundRecord.ts.millisecondsSinceEpoch - candidate.ts).abs();
          if (diffMs <= const Duration(days: 30).inMilliseconds) {
            return EventCorrelationResult(
              matchedTransactionId: candidate.id,
              linkType: TransactionLinkType.refunds,
              basis: 'refund_ref_match:$normRef',
              confidence: 0.99,
            );
          }
        }
      }
    }

    // Tier 2: Exact or partial amount + same counterparty within 30 days
    final recordMerchant = refundRecord.merchantRaw?.toUpperCase();
    final matchingCandidates = <Transaction>[];

    for (final candidate in candidates) {
      if (candidate.direction != 'debit') continue;
      if (hasRefDisagreement(refundRecord.refId, candidate.refId)) continue;

      final diffMs = (refundRecord.ts.millisecondsSinceEpoch - candidate.ts).abs();
      if (diffMs <= const Duration(days: 30).inMilliseconds) {
        final amountMatch = (refundRecord.amount - candidate.amount).abs() <= 0.01 || refundRecord.amount <= candidate.amount;
        final candMerchant = candidate.merchantRaw?.toUpperCase();
        final merchantMatch = recordMerchant != null && candMerchant != null && (recordMerchant == candMerchant || recordMerchant.startsWith(candMerchant) || candMerchant.startsWith(recordMerchant));

        if (amountMatch && merchantMatch) {
          matchingCandidates.add(candidate);
        }
      }
    }

    if (matchingCandidates.length == 1) {
      final match = matchingCandidates.single;
      final isFullRefund = (refundRecord.amount - match.amount).abs() <= 0.01;
      return EventCorrelationResult(
        matchedTransactionId: match.id,
        linkType: TransactionLinkType.refunds,
        basis: isFullRefund ? 'refund_full_counterparty_match' : 'refund_partial_counterparty_match',
        confidence: isFullRefund ? 0.95 : 0.91,
      );
    }

    return null;
  }
}
