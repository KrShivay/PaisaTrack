import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Read-and-correct view of a single transaction (T-038).
///
/// Shows every frozen §6.2 field plus status, with a confidence-trail
/// placeholder (full enrichment trail lands in Phase 3). Category and
/// description are editable; saving writes one `feedback` row per changed
/// field (context `'detail_edit'`) atomically with the update, via
/// [TransactionRepository.updateWithFeedback].
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.txnId});

  final String txnId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _descriptionController = TextEditingController();
  bool _editsSeeded = false;
  String? _categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Seeds the editable fields once from the loaded row, so in-progress
  /// edits are not clobbered by stream re-emissions.
  void _seedEdits(TransactionDetail detail) {
    if (_editsSeeded) return;
    _editsSeeded = true;
    _categoryId = detail.txn.categoryId;
    _descriptionController.text = detail.txn.description ?? '';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final repository = ref.read(transactionRepositoryProvider(database));
      final description = _descriptionController.text.trim();
      final written = await repository.updateWithFeedback(
        txnId: widget.txnId,
        categoryId: Value(_categoryId),
        description: Value(description.isEmpty ? null : description),
      );
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(written > 0 ? 'Saved' : 'No changes to save'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save changes')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(transactionDetailProvider(widget.txnId));

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: switch (detail) {
        AsyncData(:final value?) => _buildDetail(context, value),
        AsyncData() => const Center(child: Text('Transaction not found')),
        AsyncError() => const Center(child: Text('Could not load transaction')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildDetail(BuildContext context, TransactionDetail detail) {
    _seedEdits(detail);
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final localizations = MaterialLocalizations.of(context);
    final txn = detail.txn;
    final isCredit = txn.direction == 'credit';
    final ts = DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true)
        .toLocal();
    final categories = ref.watch(categoryListProvider);

    return ListView(
      padding: AppSpacing.screen,
      children: [
        Text(
          '${isCredit ? '+' : '-'}${formatInr(txn.amount)}',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: isCredit ? paisa.credit : paisa.debit,
            fontWeight: FontWeight.w600,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${localizations.formatMediumDate(ts)} · '
          '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(ts))}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Rendered only once categories have loaded, so the current category
        // id is always among the dropdown's items (a stale/unknown id would
        // otherwise trip the dropdown's value assertion).
        switch (categories) {
          AsyncData(:final value) => DropdownButtonFormField<String?>(
              initialValue: value.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Uncategorized'),
                ),
                for (final category in value)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
          _ => const TextField(
              enabled: false,
              decoration: InputDecoration(labelText: 'Category'),
            ),
        },
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save changes'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _FieldRow(label: 'Direction', value: txn.direction),
        _FieldRow(label: 'Channel', value: txn.channel),
        _FieldRow(
          label: 'Merchant',
          value: detail.merchantName ?? txn.merchantRaw,
        ),
        _FieldRow(label: 'Counterparty VPA', value: txn.counterpartyVpa),
        _FieldRow(label: 'Account', value: txn.accountHint),
        _FieldRow(
          label: 'Balance after',
          value: txn.balanceAfter == null
              ? null
              : formatInr(txn.balanceAfter!),
        ),
        _FieldRow(label: 'Reference', value: txn.refId),
        _FieldRow(label: 'Status', value: txn.status),
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Confidence trail', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _FieldRow(label: 'Parse source', value: txn.parseSource),
                _FieldRow(
                  label: 'Parse confidence',
                  value: detail.parseConfidence?.toStringAsFixed(2),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Enrichment and decision steps will appear here once the '
                  'categorization pipeline records them (Phase 3).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Label/value row for read-only detail fields; null values render as '—'.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value ?? '—', style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
