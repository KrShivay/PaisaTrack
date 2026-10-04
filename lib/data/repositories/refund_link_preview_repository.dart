import 'package:drift/drift.dart';

import '../analytics/financial_eligibility.dart';
import '../db/database.dart';
import '../models/refund_link_preview.dart';
import '../models/source_currency.dart';

/// Builds a read-only preview from persisted transaction and relationship rows.
///
/// Candidate lookup uses equality on the indexed raw `ref_id` column. It does
/// not scan history or extract a digit run, since doing so could merge distinct
/// full references. Purchase dates must be on or before the refund date.
///
/// Pair arithmetic supports at most six fractional decimal places, regardless
/// of currency denomination. Source doubles are retained; unsupported or
/// display-unrepresentable values abstain instead of being rounded.
class RefundLinkPreviewRepository {
  const RefundLinkPreviewRepository(this._database);

  final AppDatabase _database;

  static const _adjustmentLinkTypes = {'refunds', 'reverses'};
  // Each ID is bound twice by the endpoint OR query; stay below SQLite's
  // commonly supported 999-variable limit.
  static const _maxLookupIds = 400;
  static const _maxReferenceRows = 400;
  static const _maxLinkRows = 2000;
  static const _decimalScale = 6;

  /// Recomputes a preview in one read transaction. This method never writes.
  Future<RefundLinkPreview> previewForRefund(String refundTransactionId) {
    return _database.transaction(() async {
      final refund = await (_database.select(_database.transactions)
            ..where((row) => row.id.equals(refundTransactionId)))
          .getSingleOrNull();
      if (refund == null) {
        return RefundLinkPreview(
          refundTransactionId: refundTransactionId,
          status: RefundLinkPreviewStatus.missingRefund,
          candidates: const [],
        );
      }

      final currency = SourceCurrency(
        code: refund.currencyCode,
        symbol: refund.currencySymbol,
      );
      final refundDate = _date(refund.ts);
      final refundAmount = refund.amount;
      if (!_baseEligible(refund) ||
          refund.direction != 'credit' ||
          !_validAmount(refundAmount)) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.invalidRefund,
        );
      }
      final refundUnits = _amountUnits(refundAmount);
      if (refundUnits == null) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
        );
      }

      final categories = await _database.select(_database.categories).get();
      final spendingCategoryById = {
        for (final category in categories) category.id: category.isSpending,
      };

      // First inspect links touching this credit. A valid existing relationship
      // is returned with its original pair evidence and no proposed amount.
      final refundLinks = await (_database.select(_database.transactionLinks)
            ..where(
              (link) =>
                  link.fromTxnId.equals(refund.id) |
                  link.toTxnId.equals(refund.id),
            )
            ..limit(_maxLinkRows + 1))
          .get();
      if (refundLinks.length > _maxLinkRows) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }
      if (refundLinks.isNotEmpty) {
        final pairResult = await _existingRefundPair(
          refund,
          refundLinks,
          spendingCategoryById,
          currency,
        );
        final pair = pairResult.candidate;
        if (pair == null) {
          return _result(
            refund,
            status: RefundLinkPreviewStatus.blocked,
            reason: pairResult.blockReason!,
          );
        }
        return RefundLinkPreview(
          refundTransactionId: refund.id,
          status: RefundLinkPreviewStatus.blocked,
          blockReason: RefundLinkPreviewBlockReason.alreadyLinked,
          refundDate: refundDate,
          refundAmount: refundAmount,
          currency: currency,
          candidates: [pair],
        );
      }

      final exactReference = refund.refId;
      if (exactReference == null || exactReference.trim().isEmpty) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.missingExactReference,
        );
      }

      // `ref_id` has an index (idx_transactions_ref_id), so the query stays
      // bounded to rows with the same complete stored reference.
      final referenceRows = await (_database.select(_database.transactions)
            ..where((row) => row.refId.equals(exactReference))
            ..limit(_maxReferenceRows + 1))
          .get();
      if (referenceRows.length > _maxReferenceRows) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }
      final candidates = referenceRows.where((candidate) {
        if (candidate.id == refund.id ||
            candidate.direction != 'debit' ||
            candidate.ts > refund.ts ||
            !_baseEligible(candidate) ||
            !_validAmount(candidate.amount)) {
          return false;
        }
        if (!currency.sameBucket(
          SourceCurrency(
            code: candidate.currencyCode,
            symbol: candidate.currencySymbol,
          ),
        )) {
          return false;
        }
        final categorySpends = candidate.categoryId == null
            ? true
            : spendingCategoryById[candidate.categoryId] ?? true;
        return FinancialEligibility.includesSpendingDebit(
          candidate,
          categoryIsSpending: categorySpends,
        );
      }).toList()
        ..sort((a, b) {
          final byDate = a.ts.compareTo(b.ts);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });

      if (candidates.isEmpty) {
        return RefundLinkPreview(
          refundTransactionId: refund.id,
          status: RefundLinkPreviewStatus.noMatch,
          refundDate: refundDate,
          refundAmount: refundAmount,
          currency: currency,
          candidates: const [],
        );
      }
      if (candidates.length + 1 > _maxLookupIds) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }

      final directLinks = await _linksTouching({
        refund.id,
        ...candidates.map((candidate) => candidate.id),
      });
      if (directLinks == null) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }
      final linkedCreditIdsByPurchase = <String, Set<String>>{};
      for (final candidate in candidates) {
        linkedCreditIdsByPurchase[candidate.id] = directLinks
            .where(
              (link) =>
                  _adjustmentLinkTypes.contains(link.linkType) &&
                  link.toTxnId == candidate.id,
            )
            .map((link) => link.fromTxnId)
            .toSet();
      }
      final allAdjustmentIds =
          linkedCreditIdsByPurchase.values.expand((ids) => ids).toSet();
      final closureIds = <String>{
        refund.id,
        ...candidates.map((candidate) => candidate.id),
        ...allAdjustmentIds,
      };
      final completeLinks = await _linksTouching(closureIds);
      if (completeLinks == null) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }
      final endpointIds = <String>{
        ...closureIds,
        ...completeLinks.map((link) => link.fromTxnId),
        ...completeLinks.map((link) => link.toTxnId),
      };
      if (endpointIds.length > _maxLookupIds) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }
      final endpointRows = await _transactionsById(endpointIds);
      if (endpointRows == null) {
        return _result(
          refund,
          status: RefundLinkPreviewStatus.blocked,
          reason: RefundLinkPreviewBlockReason.lookupLimitExceeded,
        );
      }

      final previewCandidates = <RefundLinkPreviewCandidate>[];
      final remainingUnitsByPurchase = <String, BigInt>{};
      for (final candidate in candidates) {
        final candidateAdjustmentIds =
            linkedCreditIdsByPurchase[candidate.id] ?? const <String>{};
        final candidateLinks = completeLinks
            .where(
              (link) =>
                  link.fromTxnId == candidate.id ||
                  link.toTxnId == candidate.id ||
                  candidateAdjustmentIds.contains(link.fromTxnId) ||
                  candidateAdjustmentIds.contains(link.toTxnId),
            )
            .toList();
        final adjustmentUnits = _existingAdjustmentUnits(
          candidate: candidate,
          links: candidateLinks,
          endpointRows: endpointRows,
          spendingCategoryById: spendingCategoryById,
        );
        final candidateUnits = _amountUnits(candidate.amount);
        if (adjustmentUnits == null || candidateUnits == null) {
          final hasUnsupportedAdjustmentPrecision = candidateLinks.any((edge) {
            if (!_adjustmentLinkTypes.contains(edge.linkType) ||
                edge.toTxnId != candidate.id) {
              return false;
            }
            final source = endpointRows[edge.fromTxnId];
            return source != null &&
                _validAmount(source.amount) &&
                _amountUnits(source.amount) == null;
          });
          return _result(
            refund,
            status: RefundLinkPreviewStatus.blocked,
            reason: candidateUnits == null || hasUnsupportedAdjustmentPrecision
                ? RefundLinkPreviewBlockReason.unsupportedAmountPrecision
                : RefundLinkPreviewBlockReason.invalidExistingLinks,
          );
        }
        final remainingUnits = candidateUnits - adjustmentUnits;
        if (remainingUnits.isNegative) {
          return _result(
            refund,
            status: RefundLinkPreviewStatus.blocked,
            reason: RefundLinkPreviewBlockReason.invalidExistingLinks,
          );
        }
        final adjustmentAmount = _amountFromUnits(adjustmentUnits);
        final remainingAmount = _amountFromUnits(remainingUnits);
        if (adjustmentAmount == null || remainingAmount == null) {
          return _result(
            refund,
            status: RefundLinkPreviewStatus.blocked,
            reason: RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
          );
        }
        remainingUnitsByPurchase[candidate.id] = remainingUnits;
        previewCandidates.add(
          RefundLinkPreviewCandidate(
            originalTransactionId: candidate.id,
            originalDate: _date(candidate.ts),
            originalGrossAmount: candidate.amount,
            existingAdjustmentAmount: adjustmentAmount,
            proposedRefundAmount: refundAmount,
            remainingRefundableAmount: remainingAmount,
          ),
        );
      }

      if (previewCandidates.length > 1) {
        return RefundLinkPreview(
          refundTransactionId: refund.id,
          status: RefundLinkPreviewStatus.ambiguous,
          refundDate: refundDate,
          refundAmount: refundAmount,
          currency: currency,
          candidates: previewCandidates,
        );
      }

      final only = previewCandidates.single;
      final remainingUnits =
          remainingUnitsByPurchase[only.originalTransactionId]!;
      if (refundUnits > remainingUnits) {
        return RefundLinkPreview(
          refundTransactionId: refund.id,
          status: RefundLinkPreviewStatus.blocked,
          blockReason: RefundLinkPreviewBlockReason.overCap,
          refundDate: refundDate,
          refundAmount: refundAmount,
          currency: currency,
          candidates: [only],
        );
      }
      return RefundLinkPreview(
        refundTransactionId: refund.id,
        status: RefundLinkPreviewStatus.ready,
        refundDate: refundDate,
        refundAmount: refundAmount,
        currency: currency,
        candidates: [only],
      );
    });
  }

  Future<List<TransactionLink>?> _linksTouching(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    if (ids.length > _maxLookupIds) return null;
    final links = await (_database.select(_database.transactionLinks)
          ..where(
            (link) =>
                link.fromTxnId.isIn(ids.toList()) |
                link.toTxnId.isIn(ids.toList()),
          )
          ..limit(_maxLinkRows + 1))
        .get();
    return links.length > _maxLinkRows ? null : links;
  }

  Future<Map<String, Transaction>?> _transactionsById(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    if (ids.length > _maxLookupIds) return null;
    final rows = await (_database.select(_database.transactions)
          ..where((row) => row.id.isIn(ids.toList())))
        .get();
    return {for (final row in rows) row.id: row};
  }

  Future<_ExistingPairResult> _existingRefundPair(
    Transaction refund,
    List<TransactionLink> refundLinks,
    Map<String, bool> spendingCategoryById,
    SourceCurrency refundCurrency,
  ) async {
    if (refundLinks.length != 1) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final link = refundLinks.single;
    if (link.fromTxnId != refund.id ||
        !_adjustmentLinkTypes.contains(link.linkType)) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final original = await (_database.select(_database.transactions)
          ..where((row) => row.id.equals(link.toTxnId)))
        .getSingleOrNull();
    if (original == null ||
        original.direction != 'debit' ||
        original.ts > refund.ts ||
        !_baseEligible(original) ||
        !_validAmount(original.amount) ||
        !refundCurrency.sameBucket(
          SourceCurrency(
            code: original.currencyCode,
            symbol: original.currencySymbol,
          ),
        )) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final categorySpends = original.categoryId == null
        ? true
        : spendingCategoryById[original.categoryId] ?? true;
    if (!FinancialEligibility.includesSpendingDebit(
      original,
      categoryIsSpending: categorySpends,
    )) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final refundUnits = _amountUnits(refund.amount);
    final originalUnits = _amountUnits(original.amount);
    if (refundUnits == null || originalUnits == null) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
      );
    }
    if (link.linkType == 'reverses' && refundUnits != originalUnits) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final directLinks = await _linksTouching({original.id});
    if (directLinks == null) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.lookupLimitExceeded,
      );
    }
    final adjustmentIds = directLinks
        .where(
          (edge) =>
              _adjustmentLinkTypes.contains(edge.linkType) &&
              edge.toTxnId == original.id,
        )
        .map((edge) => edge.fromTxnId)
        .toSet();
    final closureIds = {original.id, ...adjustmentIds};
    final completeLinks = await _linksTouching(closureIds);
    if (completeLinks == null) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.lookupLimitExceeded,
      );
    }
    final endpointIds = <String>{
      ...closureIds,
      ...completeLinks.map((edge) => edge.fromTxnId),
      ...completeLinks.map((edge) => edge.toTxnId),
    };
    final endpointRows = await _transactionsById(endpointIds);
    if (endpointRows == null) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.lookupLimitExceeded,
      );
    }
    final adjustmentUnits = _existingAdjustmentUnits(
      candidate: original,
      links: completeLinks,
      endpointRows: endpointRows,
      spendingCategoryById: spendingCategoryById,
    );
    if (adjustmentUnits == null) {
      final unsupported = completeLinks.any((edge) {
        if (!_adjustmentLinkTypes.contains(edge.linkType) ||
            edge.toTxnId != original.id) {
          return false;
        }
        final source = endpointRows[edge.fromTxnId];
        return source != null &&
            _validAmount(source.amount) &&
            _amountUnits(source.amount) == null;
      });
      return _ExistingPairResult.blocked(
        unsupported
            ? RefundLinkPreviewBlockReason.unsupportedAmountPrecision
            : RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    if (adjustmentUnits > originalUnits) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.invalidExistingLinks,
      );
    }
    final existingAmount = _amountFromUnits(adjustmentUnits);
    final remainingAmount = _amountFromUnits(originalUnits - adjustmentUnits);
    if (existingAmount == null || remainingAmount == null) {
      return const _ExistingPairResult.blocked(
        RefundLinkPreviewBlockReason.unsupportedAmountPrecision,
      );
    }
    return _ExistingPairResult.ready(
      RefundLinkPreviewCandidate(
        originalTransactionId: original.id,
        originalDate: _date(original.ts),
        originalGrossAmount: original.amount,
        existingAdjustmentAmount: existingAmount,
        proposedRefundAmount: 0,
        remainingRefundableAmount: remainingAmount,
      ),
    );
  }

  BigInt? _existingAdjustmentUnits({
    required Transaction candidate,
    required List<TransactionLink> links,
    required Map<String, Transaction> endpointRows,
    required Map<String, bool> spendingCategoryById,
  }) {
    // The caller provides the complete link closure of the candidate and its
    // adjustment credits. Any edge in that closure with a different type or
    // endpoint is a conflicting classification and requires review.
    final relevant = links;
    final seen = <String>{};
    final seenOutgoing = <String>{};
    var total = BigInt.zero;
    var reversalCount = 0;
    for (final link in relevant) {
      final edgeKey =
          '${link.linkType}\u0000${link.fromTxnId}\u0000${link.toTxnId}';
      if (!seen.add(edgeKey) ||
          link.toTxnId != candidate.id ||
          !_adjustmentLinkTypes.contains(link.linkType) ||
          !seenOutgoing.add(link.fromTxnId)) {
        return null;
      }
      final source = endpointRows[link.fromTxnId];
      final sourceUnits = source == null ? null : _amountUnits(source.amount);
      final candidateUnits = _amountUnits(candidate.amount);
      if (source == null ||
          source.direction != 'credit' ||
          !_baseEligible(source) ||
          source.ts < candidate.ts ||
          !_validAmount(source.amount) ||
          sourceUnits == null ||
          candidateUnits == null ||
          !_sameCurrency(source, candidate)) {
        return null;
      }
      final categorySpends = candidate.categoryId == null
          ? true
          : spendingCategoryById[candidate.categoryId] ?? true;
      if (!FinancialEligibility.includesSpendingDebit(
        candidate,
        categoryIsSpending: categorySpends,
      )) {
        return null;
      }
      if (link.linkType == 'reverses') {
        reversalCount++;
        if (reversalCount > 1 || sourceUnits != candidateUnits) return null;
      }
      total += sourceUnits;
      if (total > candidateUnits) return null;
    }
    return total;
  }

  RefundLinkPreview _result(
    Transaction refund, {
    required RefundLinkPreviewStatus status,
    required RefundLinkPreviewBlockReason reason,
  }) =>
      RefundLinkPreview(
        refundTransactionId: refund.id,
        status: status,
        blockReason: reason,
        refundDate: _date(refund.ts),
        refundAmount: refund.amount,
        currency: SourceCurrency(
          code: refund.currencyCode,
          symbol: refund.currencySymbol,
        ),
        candidates: const [],
      );

  static bool _baseEligible(Transaction row) =>
      !row.isDeleted &&
      !row.isNotTransaction &&
      row.duplicateOfTxnId == null &&
      !row.isAnalyticsExcluded &&
      row.ownedTransferId == null &&
      row.lifecycleState == 'settled';

  static bool _validAmount(double amount) => amount.isFinite && amount > 0;

  static BigInt? _amountUnits(double amount) {
    if (!amount.isFinite || amount < 0) return null;
    final decimal = amount.toString();
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(decimal);
    if (match == null) return null;
    final whole = match.group(1)!;
    final rawFraction = match.group(2) ?? '';
    final fraction = rawFraction.replaceFirst(RegExp(r'0+$'), '');
    if (fraction.length > _decimalScale) return null;
    final paddedFraction = fraction.padRight(_decimalScale, '0');
    return BigInt.parse(whole) * BigInt.from(10).pow(_decimalScale) +
        BigInt.parse(paddedFraction.isEmpty ? '0' : paddedFraction);
  }

  static double? _amountFromUnits(BigInt units) {
    final amount =
        units.toDouble() / BigInt.from(10).pow(_decimalScale).toDouble();
    return _amountUnits(amount) == units ? amount : null;
  }

  static bool _sameCurrency(Transaction a, Transaction b) =>
      SourceCurrency(code: a.currencyCode, symbol: a.currencySymbol).sameBucket(
        SourceCurrency(code: b.currencyCode, symbol: b.currencySymbol),
      );

  static DateTime _date(int ts) =>
      DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
}

class _ExistingPairResult {
  const _ExistingPairResult.ready(this.candidate) : blockReason = null;

  const _ExistingPairResult.blocked(this.blockReason) : candidate = null;

  final RefundLinkPreviewCandidate? candidate;
  final RefundLinkPreviewBlockReason? blockReason;
}
