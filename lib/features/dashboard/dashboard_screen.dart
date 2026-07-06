import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import 'dashboard_providers.dart';

/// Basic month-summary dashboard: total spent vs. total received this month.
///
/// Styling follows docs/design-system.md: semantic money colors come from
/// [PaisaColors], amounts render with tabular figures, and spacing/radius use
/// the token scale.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthDirectionTotalsProvider);
    final paisa = PaisaColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('This month')),
      body: Padding(
        padding: AppSpacing.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TotalCard(
              label: 'Spent',
              amount: totals.debitTotal,
              color: paisa.debit,
              icon: Icons.arrow_outward,
            ),
            const SizedBox(height: AppSpacing.md),
            _TotalCard(
              label: 'Received',
              amount: totals.creditTotal,
              color: paisa.credit,
              icon: Icons.arrow_downward,
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
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              formatInr(amount),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
