import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dashboard_providers.dart';

/// Basic month-summary dashboard: total spent vs. total received this month.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthDirectionTotalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('This month')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TotalCard(
              label: 'Spent',
              amount: totals.debitTotal,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            _TotalCard(
              label: 'Received',
              amount: totals.creditTotal,
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
