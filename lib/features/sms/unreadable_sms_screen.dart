import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/parser_version.dart';
import '../../core/constants.dart';
import '../../core/widgets/bloom/bloom_sheet_scaffold.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/raw_sms_repository.dart';
import 'sms_lookup_sheet.dart';

/// Content-free retained-failure counts for the user-facing capture status.
final retainedSmsFailureSummaryProvider =
    StreamProvider.autoDispose<RetainedSmsFailureSummary>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(rawSmsRepositoryProvider(database)).watchRetainedFailures(),
    loading: () => const Stream<RetainedSmsFailureSummary>.empty(),
    error: (error, stackTrace) =>
        Stream<RetainedSmsFailureSummary>.error(error, stackTrace),
  );
});

/// Explains retained parse failures without exposing SMS bodies or identifiers.
class UnreadableSmsScreen extends ConsumerWidget {
  const UnreadableSmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(retainedSmsFailureSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Messages we couldn't read")),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text('Could not load message status'),
        ),
        data: (value) => _FailureSummaryBody(summary: value),
      ),
    );
  }
}

class _FailureSummaryBody extends StatelessWidget {
  const _FailureSummaryBody({required this.summary});

  final RetainedSmsFailureSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          summary.total == 0
              ? 'No unreadable messages are retained.'
              : '${summary.total} message${summary.total == 1 ? '' : 's'} could not be read',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'These counts contain no message text, sender names, or message IDs.',
          style: theme.textTheme.bodyMedium,
        ),
        if (summary.total > 0) ...[
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                _ReasonRow(
                  icon: Icons.help_outline,
                  label: 'Could not match a transaction',
                  count: summary.countFor(SmsFailureReason.unparsed),
                ),
                const Divider(height: 1),
                _ReasonRow(
                  icon: Icons.sync_problem_outlined,
                  label: 'Temporary processing issue',
                  count: summary.countFor(SmsFailureReason.processingError),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'For privacy, message details are kept on this phone for up to '
              '${AppConstants.rawSmsRetentionDays} days so a parser update can '
              'retry them. After that, the details are deleted and are not '
              'shown here.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => showBloomModalSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const SmsLookupSheet(startImmediately: true),
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry by scanning the inbox'),
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        '$count',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
