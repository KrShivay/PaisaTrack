import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/normalized_transaction_record.dart'
    show FieldEvidence;

/// Builds the "Field Evidence Spans" widget for a parsed SMS transaction.
///
/// Returns a purged-message placeholder when [rawSmsBody] is null or empty,
/// a plain [SelectableText] when there are no spans, and an annotated
/// [SelectableText.rich] with per-field highlight badges otherwise.
Widget buildEvidenceSpans(
  String? rawSmsBody,
  List<FieldEvidence>? evidence,
  bool isDark,
  double? parseConfidence,
) {
  if (rawSmsBody == null || rawSmsBody.isEmpty) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Source message purged per retention policy',
        style: AppTheme.bloomDisplay(
          12,
          FontWeight.w400,
          color: isDark
              ? AppColorTokens.bloomDarkTextTertiary
              : AppColorTokens.inkTertiary,
        ),
      ),
    );
  }

  final evList = evidence ?? [];
  if (evList.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FIELD EVIDENCE SPANS',
          style: AppTheme.bloomDisplay(
            10,
            FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          rawSmsBody,
          style: AppTheme.bloomMono(12, FontWeight.w400),
        ),
      ],
    );
  }

  final sorted = [...evList]..sort((a, b) => a.start.compareTo(b.start));
  final spans = <InlineSpan>[];
  var currentOffset = 0;
  final textLength = rawSmsBody.length;

  for (final ev in sorted) {
    if (ev.start < currentOffset || ev.start >= textLength) continue;
    if (ev.start > currentOffset) {
      spans.add(TextSpan(text: rawSmsBody.substring(currentOffset, ev.start)));
    }
    final end = math.min(ev.end, textLength);
    final verbatimText = rawSmsBody.substring(ev.start, end);
    final highlightColor = _highlightColorFor(ev.field, isDark);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: highlightColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            verbatimText,
            style: AppTheme.bloomMono(
              12,
              FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
    currentOffset = end;
  }
  if (currentOffset < textLength) {
    spans.add(TextSpan(text: rawSmsBody.substring(currentOffset)));
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'FIELD EVIDENCE SPANS',
        style: AppTheme.bloomDisplay(
          10,
          FontWeight.w600,
          letterSpacing: 0.1,
          color: isDark
              ? AppColorTokens.bloomDarkTextTertiary
              : AppColorTokens.inkTertiary,
        ),
      ),
      const SizedBox(height: 6),
      SelectableText.rich(
        TextSpan(
          children: spans,
          style: AppTheme.bloomMono(12, FontWeight.w400),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final ev in evList)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColorTokens.bloomDarkBase
                    : const Color(0xFFEFEBFD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${ev.field}: "${ev.verbatim}" (${ev.extractor}, '
                '${(parseConfidence ?? 1.0) * 100 ~/ 1}%)',
                style: AppTheme.bloomMono(
                  10,
                  FontWeight.w500,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

Color _highlightColorFor(String field, bool isDark) {
  switch (field.toLowerCase()) {
    case 'amount':
      return isDark
          ? AppColorTokens.emerald.withValues(alpha: 0.35)
          : const Color(0xFFD1F4E0);
    case 'direction':
      return isDark
          ? AppColorTokens.violetPrimary.withValues(alpha: 0.35)
          : const Color(0xFFE2D9F3);
    case 'date':
    case 'ts':
      return isDark
          ? AppColorTokens.warningDark.withValues(alpha: 0.35)
          : const Color(0xFFFBE6B5);
    default:
      return isDark
          ? AppColorTokens.royalBlue.withValues(alpha: 0.35)
          : const Color(0xFFD9EEF9);
  }
}
