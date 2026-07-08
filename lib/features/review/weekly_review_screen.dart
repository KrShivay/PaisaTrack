import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/paisa_colors.dart';
import '../../data/db/database_provider.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/transactions_providers.dart';

class WeeklyReviewScreen extends ConsumerWidget {
  const WeeklyReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: switch (queue) {
        AsyncData(:final value) when value.isEmpty => const _EmptyReviewState(),
        AsyncData(:final value) => _ReviewList(items: value),
        AsyncError() =>
          const Center(child: Text('Could not load review queue')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ReviewList extends ConsumerWidget {
  const _ReviewList({required this.items});

  final List<TransactionReviewItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return Dismissible(
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
          child: _ReviewTile(item: item),
        );
      },
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({required this.item});

  final TransactionReviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isCredit = item.direction == TransactionDirection.credit;
    final amountColor = isCredit ? paisa.credit : paisa.debit;
    final categoryColor = CategoryVisuals.color(item.categoryId);

    return ListTile(
      onTap: () => _showCorrectionSheet(context, ref, item),
      leading: Container(
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
  final categories = ref.read(categoryListProvider).valueOrNull ?? const [];
  if (categories.isEmpty) return;
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
