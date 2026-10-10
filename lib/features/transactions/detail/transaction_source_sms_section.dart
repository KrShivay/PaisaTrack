import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/repositories/transaction_sms_repository.dart';
import 'detail_clipboard.dart';
import 'transaction_detail_formatting.dart';

/// Human label for a linked message that is not the primary one.
String smsRoleLabel(TransactionSmsRole role, String? kind) {
  // Kind values are written by SupportingSmsLinker (ADR 0032).
  switch (kind) {
    case 'dividend':
      return 'Dividend advice';
    case 'rd_instalment':
      return 'RD instalment';
    case 'emi_notice':
      return 'EMI notice';
    case 'collect_request':
      return 'UPI payment request';
  }
  return switch (role) {
    TransactionSmsRole.primary => 'Source message',
    TransactionSmsRole.duplicate => 'Duplicate alert',
    TransactionSmsRole.supporting => 'Related message',
  };
}

/// Always-expanded "Source SMS" section: the primary message first, then any
/// other messages linked to the transaction, each selectable and copyable.
class TransactionSourceSmsSection extends ConsumerWidget {
  const TransactionSourceSmsSection({
    super.key,
    required this.txnId,
    required this.hasSmsLink,
    required this.fallbackBody,
    required this.parseSource,
    required this.parseConfidence,
    required this.isNotTransaction,
    required this.onMarkNotTransaction,
  });

  final String txnId;
  final bool hasSmsLink;
  final String? fallbackBody;
  final String parseSource;
  final double? parseConfidence;
  final bool isNotTransaction;
  final VoidCallback? onMarkNotTransaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linked =
        ref.watch(transactionSmsMessagesProvider(txnId)).valueOrNull ??
            const <TransactionSmsMessage>[];
    if (!hasSmsLink && linked.isEmpty) return const SizedBox.shrink();

    final primaryIndex =
        linked.indexWhere((m) => m.role == TransactionSmsRole.primary);
    final primary =
        linked.isEmpty ? null : linked[primaryIndex < 0 ? 0 : primaryIndex];
    final others = [
      for (final m in linked)
        if (!identical(m, primary)) m,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SOURCE SMS',
          style: AppTheme.bloomDisplay(
            12,
            FontWeight.w700,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 10),
        _SmsCard(
          isDark: isDark,
          label: null,
          sender: primary?.sender,
          receivedAt: primary?.receivedAt,
          body: primary?.body ?? fallbackBody,
          footer: _ProvenanceFooter(
            parseSource: parseSource,
            parseConfidence: parseConfidence,
            isNotTransaction: isNotTransaction,
            onMarkNotTransaction: onMarkNotTransaction,
            isDark: isDark,
          ),
        ),
        for (final message in others) ...[
          const SizedBox(height: 10),
          _SmsCard(
            key: ValueKey('related_sms_${message.smsId}'),
            isDark: isDark,
            label: smsRoleLabel(message.role, message.kind),
            sender: message.sender,
            receivedAt: message.receivedAt,
            body: message.body,
          ),
        ],
      ],
    );
  }
}

class _SmsCard extends StatelessWidget {
  const _SmsCard({
    super.key,
    required this.isDark,
    required this.label,
    required this.sender,
    required this.receivedAt,
    required this.body,
    this.footer,
  });

  final bool isDark;
  final String? label;
  final String? sender;
  final DateTime? receivedAt;
  final String? body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF132820) : const Color(0xFFF1FBF6);
    final border = isDark ? const Color(0xFF1B4D3E) : const Color(0xFFC9EEDD);
    final textColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final metaColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final text = body?.trim();
    final meta = [
      if (sender != null && sender!.trim().isNotEmpty) sender!.trim(),
      if (receivedAt != null) formatDetailDate(receivedAt!),
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                label!,
                style: AppTheme.bloomDisplay(
                  12,
                  FontWeight.w700,
                  color: AppColorTokens.emerald,
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meta,
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w500,
                  color: metaColor,
                ),
              ),
            ),
          if (text == null || text.isEmpty) ...[
            Text(
              'Source message not available',
              style: AppTheme.bloomDisplay(
                13,
                FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use Restore SMS sources in Settings to re-read your inbox.',
              style:
                  AppTheme.bloomDisplay(12, FontWeight.w400, color: metaColor),
            ),
          ] else ...[
            SelectableText(
              text,
              style: AppTheme.bloomMono(12, FontWeight.w400, color: textColor)
                  .copyWith(height: 1.6),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => copyDetailValue(
                  context,
                  text: text,
                  label: 'message',
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy message'),
              ),
            ),
          ],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _ProvenanceFooter extends StatelessWidget {
  const _ProvenanceFooter({
    required this.parseSource,
    required this.parseConfidence,
    required this.isNotTransaction,
    required this.onMarkNotTransaction,
    required this.isDark,
  });

  final String parseSource;
  final double? parseConfidence;
  final bool isNotTransaction;
  final VoidCallback? onMarkNotTransaction;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onMarkNotTransaction,
            icon: Icon(
              isNotTransaction ? Icons.check_circle_outline : Icons.block,
              size: 18,
            ),
            label: Text(
              isNotTransaction
                  ? 'Marked not a transaction'
                  : 'Not a transaction',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              key: const ValueKey('parser_provenance_badge'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0E7A56),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Parsed locally',
                      style: AppTheme.bloomDisplay(
                        11,
                        FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              parserSourceLabel(parseSource, parseConfidence),
              style: AppTheme.bloomMono(
                11,
                FontWeight.w500,
                color: isDark
                    ? AppColorTokens.bloomDarkTextSecondary
                    : AppColorTokens.inkSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
