import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/paisa_colors.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Lists parsed transactions, newest first.
///
/// Tiles follow the design-system recipe (docs/design-system.md §9): leading
/// category tile, merchant title, category subtitle, signed tabular amount in
/// the semantic direction color.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: switch (transactions) {
        AsyncData(:final value) when value.isEmpty =>
          const Center(child: Text('No transactions yet')),
        AsyncData(:final value) => _TransactionListView(items: value),
        AsyncError() => const Center(child: Text('Could not load transactions')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TransactionListView extends StatelessWidget {
  const _TransactionListView({required this.items});

  final List<TransactionListItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _TransactionTile(item: items[index]),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item});

  final TransactionListItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isCredit = item.direction == TransactionDirection.credit;
    final sign = isCredit ? '+' : '-';
    final amountColor = isCredit ? paisa.credit : paisa.debit;
    final categoryColor = CategoryVisuals.colorForName(item.categoryName);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: categoryColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          CategoryVisuals.iconForName(item.categoryName),
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
        '$sign₹${item.amount.toStringAsFixed(2)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}
