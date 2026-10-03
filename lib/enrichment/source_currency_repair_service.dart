import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../capture/template_engine/field_normalizer.dart';
import '../data/confidence_payload.dart';
import '../data/db/database.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/source_currency.dart';

/// A source-backed proposal to label one legacy transaction as INR.
///
/// This deliberately carries only the amount span and currency token, never
/// the raw SMS body.
class SourceCurrencyRepairPreview {
  const SourceCurrencyRepairPreview({
    required this.transactionId,
    required this.smsId,
    required this.amountPaise,
    required this.currencyToken,
    required this.amountStart,
    required this.amountEnd,
    required this.amountVerbatim,
  });

  final String transactionId;
  final String smsId;
  final int amountPaise;
  final String currencyToken;
  final int amountStart;
  final int amountEnd;
  final String amountVerbatim;

  @override
  bool operator ==(Object other) =>
      other is SourceCurrencyRepairPreview &&
      transactionId == other.transactionId &&
      smsId == other.smsId &&
      amountPaise == other.amountPaise &&
      currencyToken == other.currencyToken &&
      amountStart == other.amountStart &&
      amountEnd == other.amountEnd &&
      amountVerbatim == other.amountVerbatim;

  @override
  int get hashCode => Object.hash(
        transactionId,
        smsId,
        amountPaise,
        currencyToken,
        amountStart,
        amountEnd,
        amountVerbatim,
      );
}

/// Explicit, per-transaction repair for legacy null currency values.
///
/// The linked source SMS (kept as provenance, ADR 0021) and persisted amount
/// evidence must agree exactly. No database scan, migration, ingest, or startup hook runs.
class SourceCurrencyRepairService {
  SourceCurrencyRepairService(this._database);

  final AppDatabase _database;
  static const _normalizer = FieldNormalizer();
  static final _amountPattern =
      RegExp(r'(?<![\d,])\d[\d,]*(?:\.\d{1,2})?(?![\d.,])');
  static final _currencyBefore = RegExp(
    r'(?<![A-Za-z0-9])(?:USD|US\$|INR\.?|Rs\.?|₹|\$)\s*$',
    caseSensitive: false,
  );
  static final _currencyAfter = RegExp(
    r'^\s*(USD|US\$|INR|Rs\.?|₹|\$)(?=\s|$|[.,])(?!\s*\d)',
    caseSensitive: false,
  );

  /// Returns a non-mutating proposal for a single transaction, if evidence is
  /// complete and unambiguous.
  Future<SourceCurrencyRepairPreview?> preview(String transactionId) async {
    final source = await _loadSource(transactionId);
    if (source == null) return null;
    return _buildPreview(source.transaction, source.sms);
  }

  /// Revalidates the proposal and updates only the two currency columns.
  Future<bool> apply(SourceCurrencyRepairPreview preview) async {
    return _database.transaction(() async {
      final source = await _loadSource(preview.transactionId);
      if (source == null ||
          _buildPreview(source.transaction, source.sms) != preview) {
        return false;
      }

      final changed = await (_database.update(_database.transactions)
            ..where(
              (row) =>
                  row.id.equals(preview.transactionId) &
                  row.currencyCode.isNull() &
                  row.currencySymbol.isNull(),
            ))
          .write(
        const TransactionsCompanion(
          currencyCode: Value('INR'),
          currencySymbol: Value('₹'),
        ),
      );
      return changed == 1;
    });
  }

  /// Reverses an applied repair only while its currency values are unchanged.
  Future<bool> undo(SourceCurrencyRepairPreview preview) async {
    return _database.transaction(() async {
      final transaction = await (_database.select(_database.transactions)
            ..where((row) => row.id.equals(preview.transactionId)))
          .getSingleOrNull();
      if (transaction == null ||
          transaction.currencyCode != 'INR' ||
          transaction.currencySymbol != '₹') {
        return false;
      }

      final changed = await (_database.update(_database.transactions)
            ..where(
              (row) =>
                  row.id.equals(preview.transactionId) &
                  row.currencyCode.equals('INR') &
                  row.currencySymbol.equals('₹'),
            ))
          .write(
        const TransactionsCompanion(
          currencyCode: Value(null),
          currencySymbol: Value(null),
        ),
      );
      return changed == 1;
    });
  }

  Future<({Transaction transaction, RawSm sms})?> _loadSource(
    String transactionId,
  ) async {
    final transaction = await (_database.select(_database.transactions)
          ..where((row) => row.id.equals(transactionId)))
        .getSingleOrNull();
    final smsId = transaction?.smsId;
    if (transaction == null || smsId == null) return null;
    final sms = await (_database.select(_database.rawSms)
          ..where((row) => row.id.equals(smsId)))
        .getSingleOrNull();
    if (sms == null) return null;

    final duplicateSmsRows = await (_database.select(_database.transactions)
          ..where((row) => row.smsId.equals(smsId)))
        .get();
    if (duplicateSmsRows.length != 1) return null;

    return (transaction: transaction, sms: sms);
  }

  SourceCurrencyRepairPreview? _buildPreview(
    Transaction transaction,
    RawSm sms,
  ) {
    if (transaction.currencyCode != null ||
        transaction.currencySymbol != null ||
        transaction.isDeleted ||
        transaction.isNotTransaction ||
        transaction.duplicateOfTxnId != null ||
        !const {'template', 'generic', 'local_llm'}.contains(
          transaction.parseSource,
        ) ||
        sms.body.trim().isEmpty) {
      return null;
    }

    final amountEvidence = (parseEvidenceFromJson(transaction.evidenceJson) ??
            const <FieldEvidence>[])
        .where(
          (item) =>
              item.field == 'amount' &&
              const {'template', 'generic_regex', 'local_llm'}
                  .contains(item.extractor),
        )
        .toList(growable: false);
    if (amountEvidence.isEmpty) return null;

    final matches = <SourceCurrencyRepairPreview>[];
    for (final evidence in amountEvidence) {
      if (evidence.start < 0 ||
          evidence.end <= evidence.start ||
          evidence.end > sms.body.length ||
          sms.body.substring(evidence.start, evidence.end) !=
              evidence.verbatim) {
        continue;
      }

      for (final number in _amountPattern.allMatches(evidence.verbatim)) {
        final double? parsed;
        try {
          parsed = _normalizer.parseOptionalAmount(number.group(0));
        } on FormatException {
          continue;
        }
        if (parsed == null ||
            !parsed.isFinite ||
            (parsed * 100).round() != (transaction.amount * 100).round()) {
          continue;
        }
        final start = evidence.start + number.start;
        final end = evidence.start + number.end;
        final currency = _currencyEvidenceAtAmount(
          sms.body,
          start,
          end,
        );
        if (currency == null ||
            currency.currency.code != 'INR' ||
            !_hasExactlyOneAdjacentToken(sms.body, start, end) ||
            SourceCurrency.fromToken(
                  currency.evidence.verbatim.replaceFirst(RegExp(r'\.$'), ''),
                )?.code !=
                'INR') {
          continue;
        }

        matches.add(
          SourceCurrencyRepairPreview(
            transactionId: transaction.id,
            smsId: sms.id,
            amountPaise: (transaction.amount * 100).round(),
            currencyToken: currency.evidence.verbatim,
            amountStart: start,
            amountEnd: end,
            amountVerbatim: sms.body.substring(start, end),
          ),
        );
      }
    }

    return matches.length == 1 ? matches.single : null;
  }

  bool _hasExactlyOneAdjacentToken(
    String body,
    int amountStart,
    int amountEnd,
  ) {
    final leftStart = math.max(0, amountStart - 16);
    final left = body.substring(leftStart, amountStart);
    final rightEnd = math.min(body.length, amountEnd + 16);
    final right = body.substring(amountEnd, rightEnd);
    final before = _currencyBefore.firstMatch(left);
    final after = _currencyAfter.firstMatch(right);
    return (before == null) != (after == null);
  }

  ({SourceCurrency currency, FieldEvidence evidence})?
      _currencyEvidenceAtAmount(
    String body,
    int amountStart,
    int amountEnd,
  ) {
    final evidence = _normalizer.currencyEvidenceAtAmount(
      body,
      amountStart,
      amountEnd,
    );
    if (evidence != null) {
      if (evidence.evidence.start >= amountEnd &&
          RegExp(r'^\s*\d').hasMatch(body.substring(evidence.evidence.end))) {
        return null;
      }
      return evidence;
    }

    final prefixStart = math.max(0, amountStart - 16);
    final prefix = body.substring(prefixStart, amountStart);
    final punctuatedInr = RegExp(
      r'(?<![A-Za-z])INR\.\s*$',
      caseSensitive: false,
    ).firstMatch(prefix);
    if (punctuatedInr == null) return null;

    const token = 'INR.';
    final tokenStart = prefixStart + punctuatedInr.start;
    return (
      currency: const SourceCurrency(code: 'INR', symbol: '₹'),
      evidence: FieldEvidence(
        field: 'currency',
        start: tokenStart,
        end: tokenStart + token.length,
        verbatim: token,
        extractor: 'source_currency_repair_fallback',
      ),
    );
  }
}
