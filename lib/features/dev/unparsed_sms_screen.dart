import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/raw_sms_repository.dart';
import 'transaction_export.dart';
import 'unparsed_sms_providers.dart';

/// Developer diagnostics screen listing raw SMS that never produced a
/// transaction (unknown template or not yet processed), so parser coverage
/// gaps are visible without a debugger.
class UnparsedSmsScreen extends ConsumerWidget {
  const UnparsedSmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unparsed = ref.watch(unparsedSmsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unparsed SMS (dev)'),
        actions: [
          // Debug-only plain-JSON transaction dump for the T-034
          // bank-statement reconciliation; compiled out of release builds.
          if (kDebugMode) const _ExportTransactionsButton(),
        ],
      ),
      body: switch (unparsed) {
        AsyncData(:final value) when value.isEmpty =>
          const Center(child: Text('No unparsed messages')),
        AsyncData(:final value) => _UnparsedListView(items: value),
        AsyncError() => const Center(child: Text('Could not load raw SMS')),
        _ => const Center(child: CircularProgressIndicator()),
      },
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
          messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
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
            sms.body,
            maxLines: 3,
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
