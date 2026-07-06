import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transactions_providers.dart';

/// Lists parsed transactions, newest first.
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
    final isCredit = item.direction == TransactionDirection.credit;
    final sign = isCredit ? '+' : '-';
    final color = isCredit ? Colors.green : Colors.red;

    return ListTile(
      title: Text(item.displayName),
      subtitle: Text(item.categoryName ?? 'Uncategorized'),
      trailing: Text(
        '$sign₹${item.amount.toStringAsFixed(2)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
