import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/generic_transaction_parser.dart';
import '../../capture/template_engine/template_trust_ledger.dart';
import '../../data/models/raw_sms.dart';
import '../../data/repositories/raw_sms_repository.dart';
import 'transaction_export.dart';
import 'unparsed_sms_providers.dart';
import 'sms_fixture_donation.dart';

/// Developer diagnostics screen listing raw SMS that never produced a
/// transaction, including the parser stages that rejected them, so coverage
/// gaps are visible without a debugger.
class UnparsedSmsScreen extends ConsumerWidget {
  const UnparsedSmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unparsed = ref.watch(unparsedSmsListProvider);
    final trustAlerts = ref.watch(templateTrustAlertsProvider).valueOrNull ??
        const <TemplateTrustEntry>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unparsed SMS (dev)'),
        actions: const [
          // Debug-only plain-JSON transaction dump for the T-034
          // bank-statement reconciliation; compiled out of release builds.
          if (kDebugMode) _ExportTransactionsButton(),
        ],
      ),
      body: Column(
        children: [
          if (trustAlerts.isNotEmpty) _TemplateTrustAlert(entries: trustAlerts),
          const _UnrecognizedSendersSummary(),
          Expanded(
            child: switch (unparsed) {
              AsyncData(:final value) when value.isEmpty =>
                const Center(child: Text('No unparsed messages')),
              AsyncData(:final value) => _UnparsedListView(
                  items: value,
                  copier: ref.read(smsFixtureCopierProvider),
                ),
              AsyncError() =>
                const Center(child: Text('Could not load raw SMS')),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

/// Shows public template ids whose amount or direction was corrected.
class _TemplateTrustAlert extends StatelessWidget {
  const _TemplateTrustAlert({required this.entries});

  final List<TemplateTrustEntry> entries;

  @override
  Widget build(BuildContext context) {
    final ids = entries.map((entry) => entry.templateId).join(', ');
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded),
        title: const Text('Template trust alert'),
        subtitle: Text('Re-author public template: $ids'),
      ),
    );
  }
}

class _ExportTransactionsButton extends ConsumerWidget {
  const _ExportTransactionsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.file_download_outlined),
      tooltip: 'Export transactions JSON (debug)',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export plaintext transaction data?'),
            content: const Text(
              'This JSON contains normalized financial data. Save it only to '
              'a destination you trust.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Choose destination'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;

        final messenger = ScaffoldMessenger.of(context);
        try {
          final saved = await ref.read(transactionJsonExportProvider.future);
          if (!context.mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content:
                  Text(saved ? 'Transactions exported' : 'Export cancelled'),
            ),
          );
        } catch (error) {
          messenger
              .showSnackBar(SnackBar(content: Text('Export failed: $error')));
        }
      },
    );
  }
}

class _UnparsedListView extends StatelessWidget {
  const _UnparsedListView({required this.items, required this.copier});

  final List<UnparsedSms> items;
  final SmsFixtureCopier copier;

  /// Recomputed at display time (T-070); no schema change, so a parser tweak is
  /// reflected without re-ingesting. Const parser has no per-row state.
  static const _parser = GenericTransactionParser();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final sms = items[index];
        final theme = Theme.of(context);
        return ListTile(
          leading: Icon(
            Icons.sms_failed_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(sms.sender),
          subtitle: Text(
            '${sms.body}\nTemplate: no match · ${_genericReason(sms)}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            tooltip: 'Share sanitized SMS',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _previewDonation(context, sms),
          ),
        );
      },
    );
  }

  Future<void> _previewDonation(BuildContext context, UnparsedSms sms) async {
    const donation = SmsFixtureDonation();
    final fixture = donation.fixture(sms);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review sanitized SMS'),
        content: SingleChildScrollView(
          child: SelectableText(fixture),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve and copy'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;

    await copier(fixture);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sanitized fixture copied')),
    );
  }

  /// Human-readable generic-parser rejection reason for one row.
  String _genericReason(UnparsedSms sms) {
    final reason = _parser.rejectionReason(
      RawSms(
        id: sms.id,
        sender: sms.sender,
        body: sms.body,
        receivedAt: sms.receivedAt,
      ),
    );
    return switch (reason) {
      GenericParseRejection.hardRejectTerm =>
        'Generic parser: non-transaction phrase',
      GenericParseRejection.noDirection =>
        'Generic parser: no debit/credit direction',
      GenericParseRejection.noAmount => 'Generic parser: no transaction amount',
      GenericParseRejection.noContextSignal =>
        'Generic parser: no account/UPI/channel signal',
      // Generic parser would accept it — the miss is upstream (template stage
      // or a post-parse validation), not the fallback guard.
      null => 'Generic parser: accepted (template-stage miss)',
    };
  }
}

class _UnrecognizedSendersSummary extends ConsumerWidget {
  const _UnrecognizedSendersSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderCounts = ref.watch(unrecognizedSenderCountsProvider);
    if (senderCounts.isEmpty) return const SizedBox.shrink();

    final topSenders =
        senderCounts.take(5).map((e) => '${e.key}: ${e.value}').join(', ');
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unrecognized Senders (${senderCounts.length} distinct)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4.0),
            Text(
              topSenders,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

