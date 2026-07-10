import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/template_engine/template_trust_ledger.dart';
import '../../data/repositories/raw_sms_repository.dart';
import 'transaction_export.dart';
import 'unparsed_sms_providers.dart';

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
          Expanded(
            child: switch (unparsed) {
              AsyncData(:final value) when value.isEmpty =>
                const Center(child: Text('No unparsed messages')),
              AsyncData(:final value) => _UnparsedListView(items: value),
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
        final messenger = ScaffoldMessenger.of(context);
        try {
          final path = await ref.read(transactionJsonExportProvider.future);
          messenger.showSnackBar(SnackBar(content: Text('Exported: $path')));
        } catch (error) {
          messenger
              .showSnackBar(SnackBar(content: Text('Export failed: $error')));
        }
      },
    );
  }
}

class _UnparsedListView extends StatelessWidget {
  const _UnparsedListView({required this.items});

  final List<UnparsedSms> items;

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
            '${sms.body}\nTemplate: no match · Generic parser: guard rejected',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
