import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/db/database.dart' show Transaction;
import '../../../data/models/normalized_transaction_record.dart'
    show FieldEvidence;
import 'transaction_detail_evidence.dart';
import 'transaction_detail_formatting.dart';

/// One labelled technical value; [mono] is used for identifiers.
class TechnicalRow {
  const TechnicalRow(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;
}

/// A titled group of technical rows.
class TechnicalGroup {
  const TechnicalGroup(this.title, this.rows);

  final String title;
  final List<TechnicalRow> rows;
}

String _sentence(String raw) {
  final words = raw.replaceAll('_', ' ').trim();
  return words.isEmpty ? raw : words[0].toUpperCase() + words.substring(1);
}

/// Groups the stored diagnostic fields (Parsing, Identity, Lifecycle) with
/// human labels. Empty values and empty groups are omitted.
List<TechnicalGroup> technicalGroups(Transaction txn) {
  String? present(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  final kind = present(txn.messageKind);
  final reason = present(txn.lifecycleReason);
  final groups = [
    TechnicalGroup('Parsing', [
      TechnicalRow('Parsed by', parserSourceLabel(txn.parseSource, null)),
      if (kind != null) TechnicalRow('Message type', _sentence(kind)),
      TechnicalRow('Review status', _sentence(txn.status)),
    ]),
    TechnicalGroup('Identity', [
      TechnicalRow('Transaction ID', txn.id, mono: true),
      if (present(txn.smsId) case final v?)
        TechnicalRow('SMS ID', v, mono: true),
      if (present(txn.merchantId) case final v?)
        TechnicalRow('Merchant ID', v, mono: true),
      if (present(txn.duplicateOfTxnId) case final v?)
        TechnicalRow('Duplicate of', v, mono: true),
      if (present(txn.ownedTransferId) case final v?)
        TechnicalRow('Transfer ID', v, mono: true),
    ]),
    TechnicalGroup('Lifecycle', [
      TechnicalRow('Lifecycle state', _sentence(txn.lifecycleState)),
      if (reason != null) TechnicalRow('Reason', _sentence(reason)),
      TechnicalRow('Created', formatDetailDate(txn.createdAt)),
      TechnicalRow('Updated', formatDetailDate(txn.updatedAt)),
      if (txn.isDeleted) const TechnicalRow('Deleted', 'Yes'),
      if (txn.isNotTransaction) const TechnicalRow('Not a transaction', 'Yes'),
      if (txn.isAnalyticsExcluded)
        const TechnicalRow('Excluded from analytics', 'Yes'),
    ]),
  ];
  return [
    for (final g in groups)
      if (g.rows.isNotEmpty) g,
  ];
}

/// Collapsed-by-default "Technical details" card.
class TransactionTechnicalDetailsCard extends StatefulWidget {
  const TransactionTechnicalDetailsCard({
    super.key,
    required this.transaction,
    required this.parseConfidence,
    required this.isLowTrustParse,
    this.evidence,
    this.rawSmsBody,
  });

  final Transaction transaction;
  final double? parseConfidence;
  final bool isLowTrustParse;
  final List<FieldEvidence>? evidence;
  final String? rawSmsBody;

  @override
  State<TransactionTechnicalDetailsCard> createState() =>
      _TransactionTechnicalDetailsCardState();
}

class _TransactionTechnicalDetailsCardState
    extends State<TransactionTechnicalDetailsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final valueColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final groups = _expanded
        ? technicalGroups(widget.transaction)
        : const <TechnicalGroup>[];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              key: const ValueKey('technical_details_toggle'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.terminal_rounded, size: 16, color: labelColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Technical details',
                        style: AppTheme.bloomDisplay(
                          13,
                          FontWeight.w600,
                          color: valueColor,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: labelColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in groups) ...[
                    const Divider(height: 20),
                    Text(
                      group.title.toUpperCase(),
                      style: AppTheme.bloomDisplay(
                        10,
                        FontWeight.w600,
                        letterSpacing: 0.1,
                        color: labelColor,
                      ),
                    ),
                    if (group.title == 'Parsing' &&
                        widget.parseConfidence != null)
                      _ConfidenceRow(
                        confidence: widget.parseConfidence!,
                        lowTrust: widget.isLowTrustParse,
                        labelColor: labelColor,
                        valueColor: valueColor,
                      ),
                    for (final row in group.rows)
                      _TechnicalRowView(
                        row: row,
                        labelColor: labelColor,
                        valueColor: valueColor,
                      ),
                  ],
                  if ((widget.rawSmsBody ?? '').isNotEmpty) ...[
                    const Divider(height: 20),
                    buildEvidenceSpans(
                      widget.rawSmsBody,
                      widget.evidence,
                      isDark,
                      widget.parseConfidence,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TechnicalRowView extends StatelessWidget {
  const _TechnicalRowView({
    required this.row,
    required this.labelColor,
    required this.valueColor,
  });

  final TechnicalRow row;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.label,
              style: AppTheme.bloomDisplay(
                11,
                FontWeight.w500,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              row.value,
              style: row.mono
                  ? AppTheme.bloomMono(12, FontWeight.w500, color: valueColor)
                  : AppTheme.bloomDisplay(
                      13,
                      FontWeight.w600,
                      color: valueColor,
                    ),
            ),
          ],
        ),
      );
}

class _ConfidenceRow extends StatelessWidget {
  const _ConfidenceRow({
    required this.confidence,
    required this.lowTrust,
    required this.labelColor,
    required this.valueColor,
  });

  final double confidence;
  final bool lowTrust;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final color =
        lowTrust ? AppColorTokens.warningDark : AppColorTokens.emerald;
    final pct = '${(confidence * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confidence',
            style: AppTheme.bloomDisplay(
              11,
              FontWeight.w500,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  pct,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Text(
                lowTrust ? 'Low trust' : 'High trust',
                style: AppTheme.bloomDisplay(
                  12,
                  FontWeight.w500,
                  color: valueColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
