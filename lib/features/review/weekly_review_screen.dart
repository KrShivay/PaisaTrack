import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/transactions_providers.dart';
import '../transactions/transaction_detail_screen.dart'
    show showParseCorrectionSheet;

class WeeklyReviewScreen extends ConsumerStatefulWidget {
  const WeeklyReviewScreen({super.key});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(reviewQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: switch (queue) {
        AsyncData(:final value) when value.isEmpty => const _EmptyReviewState(),
        AsyncData(:final value) => _ReviewList(
            items: value,
            selectedIds: _visibleSelection(value),
            onToggle: _toggle,
            onSelectAll: () => _selectAll(value),
            onConfirmSelected: () => _confirm(
              _visibleSelection(value),
              successLabel: 'transactions confirmed',
            ),
            onConfirmGroup: (ids) => _confirm(
              ids,
              successLabel: 'group transactions confirmed',
            ),
          ),
        AsyncError() => const ErrorStateView(
            message: 'Could not load the review queue.',
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Set<String> _visibleSelection(List<TransactionReviewItem> items) {
    final visibleIds = items.map((item) => item.id).toSet();
    return _selectedIds.where(visibleIds.contains).toSet();
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectAll(List<TransactionReviewItem> items) {
    final ids = items.map((item) => item.id).toSet();
    setState(() {
      if (ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _confirm(
    Iterable<String> ids, {
    required String successLabel,
  }) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _repository(ref).confirmMany(txnIds: selected);
      if (!mounted) return;
      setState(() => _selectedIds.removeAll(selected));
      messenger.showSnackBar(
        SnackBar(content: Text('$count $successLabel')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Confirmation failed: $error')),
      );
    }
  }
}

class _ReviewList extends ConsumerWidget {
  const _ReviewList({
    required this.items,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
    required this.onConfirmSelected,
    required this.onConfirmGroup,
  });

  final List<TransactionReviewItem> items;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onConfirmSelected;
  final void Function(Set<String> ids) onConfirmGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<TransactionReviewItem>>{};
    for (final item in items) {
      final key = item.counterpartyKey ??
          'display:${item.displayName.trim().toLowerCase()}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    final allSelected = items.every((item) => selectedIds.contains(item.id));
    final someSelected = selectedIds.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Checkbox(
                value: allSelected
                    ? true
                    : someSelected
                        ? null
                        : false,
                tristate: true,
                onChanged: (_) => onSelectAll(),
              ),
              const Expanded(child: Text('Select all visible')),
              FilledButton.icon(
                onPressed: someSelected ? onConfirmSelected : null,
                icon: const Icon(Icons.done_all),
                label: Text('Confirm selected (${selectedIds.length})'),
              ),
            ],
          ),
        ),
        for (final entry in groups.entries) ...[
          _ReviewGroupHeader(
            groupKey: entry.key,
            label: entry.value.first.displayName,
            count: entry.value.length,
            onConfirm: () =>
                onConfirmGroup(entry.value.map((item) => item.id).toSet()),
          ),
          for (final item in entry.value) ...[
            Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              background: const ColoredBox(
                color: Color(0xFF166534),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: AppSpacing.lg),
                    child: Icon(Icons.check, color: Colors.white),
                  ),
                ),
              ),
              confirmDismiss: (_) async {
                await _repository(ref).confirm(txnId: item.id);
                return true;
              },
              child: _ReviewTile(
                item: item,
                selected: selectedIds.contains(item.id),
                onSelected: (selected) => onToggle(item.id, selected),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }
}

class _ReviewGroupHeader extends StatelessWidget {
  const _ReviewGroupHeader({
    required this.groupKey,
    required this.label,
    required this.count,
    required this.onConfirm,
  });

  final String groupKey;
  final String label;
  final int count;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label · $count',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(
              key: ValueKey('confirm_group_$groupKey'),
              onPressed: onConfirm,
              child: const Text('Confirm group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({
    required this.item,
    required this.selected,
    required this.onSelected,
  });

  final TransactionReviewItem item;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isCredit = item.direction == TransactionDirection.credit;
    final amountColor = isCredit ? paisa.credit : paisa.debit;
    final categoryColor = CategoryVisuals.color(item.categoryId);

    return ListTile(
      onTap: () => _showCorrectionSheet(context, ref, item),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: ValueKey('select_${item.id}'),
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CategoryVisuals.icon(item.categoryIcon),
              size: 20,
              color: categoryColor,
            ),
          ),
        ],
      ),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.categoryName ?? 'Uncategorized',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        '${isCredit ? '+' : '-'}${formatInr(item.amount)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  const _EmptyReviewState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('All caught up', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'New uncertain transactions will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showCorrectionSheet(
  BuildContext context,
  WidgetRef ref,
  TransactionReviewItem item,
) async {
  final screenContext = context;
  final categories = await ref.read(categoryListProvider.future);
  if (!context.mounted || categories.isEmpty) return;
  var selectedId = item.categoryId ?? categories.first.id;

  final categoryId = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: AppSpacing.screen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Correct category',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (item.isLowTrustParse) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Parsed correctly?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton.tonal(
                        onPressed: () async {
                          await _repository(ref).confirmParse(txnId: item.id);
                          if (screenContext.mounted) {
                            ScaffoldMessenger.of(screenContext).showSnackBar(
                              const SnackBar(content: Text('Parse confirmed')),
                            );
                          }
                        },
                        child: const Text('Confirm parse'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final correction = await showParseCorrectionSheet(
                            screenContext,
                            amount: item.amount,
                            direction: item.direction.wireName,
                            merchantRaw: item.merchantRaw ?? item.displayName,
                          );
                          if (correction == null) return;
                          await _repository(ref).updateWithFeedback(
                            txnId: item.id,
                            amount: Value(correction.amount),
                            direction: Value(correction.direction),
                            merchantRaw: Value(correction.merchantRaw),
                            context: 'parse_confirm',
                            recordParseCorrections: true,
                          );
                          if (screenContext.mounted) {
                            ScaffoldMessenger.of(screenContext).showSnackBar(
                              const SnackBar(
                                content: Text('Parse correction saved'),
                              ),
                            );
                          }
                        },
                        child: const Text('Fix parse'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => selectedId = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(selectedId),
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (categoryId == null) return;
  await _repository(ref).correctWithRule(
    txnId: item.id,
    categoryId: categoryId,
    context: 'batch_review',
  );
}

TransactionRepository _repository(WidgetRef ref) {
  final database = ref.read(appDatabaseProvider).valueOrNull;
  if (database == null) {
    throw StateError('Database is not ready');
  }
  return ref.read(transactionRepositoryProvider(database));
}
