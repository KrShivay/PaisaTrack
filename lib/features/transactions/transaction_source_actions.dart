import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import 'transactions_providers.dart';

/// Explicit provenance actions shared by transaction detail and review.
class TransactionSourceActions extends ConsumerWidget {
  const TransactionSourceActions({
    super.key,
    required this.txnId,
    this.fallbackVpa,
  });

  final String txnId;
  final String? fallbackVpa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(transactionSourceProvider(txnId)).valueOrNull;
    final vpa = _nonEmpty(source?.counterpartyVpa) ?? _nonEmpty(fallbackVpa);
    final smsBody = _nonEmpty(source?.smsBody);
    if (vpa == null && smsBody == null) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        if (vpa != null)
          OutlinedButton.icon(
            key: ValueKey('copy_vpa_$txnId'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: vpa));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('VPA copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy VPA'),
          ),
        if (smsBody != null)
          OutlinedButton.icon(
            key: ValueKey('view_sms_$txnId'),
            onPressed: () => _showSourceSms(
              context,
              sender: source?.smsSender,
              body: smsBody,
              receivedAt: source?.smsReceivedAt,
            ),
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: const Text('View source SMS'),
          ),
      ],
    );
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<void> _showSourceSms(
  BuildContext context, {
  required String? sender,
  required String body,
  required DateTime? receivedAt,
}) {
  final localizations = MaterialLocalizations.of(context);
  final receivedLabel = receivedAt == null
      ? null
      : '${localizations.formatMediumDate(receivedAt.toLocal())} · '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(receivedAt.toLocal()))}';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen.left,
          AppSpacing.sm,
          AppSpacing.screen.right,
          AppSpacing.screen.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Source SMS', style: Theme.of(context).textTheme.titleLarge),
            if (_nonEmpty(sender) case final sender?) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [sender, receivedLabel].whereType<String>().join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(body),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Raw SMS is available only during the app’s retention window.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}
