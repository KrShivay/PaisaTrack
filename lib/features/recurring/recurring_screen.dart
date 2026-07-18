import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../../core/widgets/app_state_views.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../transactions/transactions_screen.dart';

/// Live recurring streams ordered by their next expected occurrence.
final recurringSeriesProvider = StreamProvider<List<RecurringSery>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => (database.select(database.recurringSeries)
          ..orderBy([
            (row) => OrderingTerm.asc(row.nextExpectedDate),
            (row) => OrderingTerm.asc(row.label),
          ]))
        .watch(),
    loading: () => const Stream<List<RecurringSery>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<RecurringSery>>.error(error, stackTrace),
  );
});

/// Subscriptions, bills, EMIs, and recurring income detected on-device.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(recurringSeriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: switch (series) {
        AsyncData(:final value) when value.isEmpty => EmptyStateView(
            illustration: AppIllustrations.bill,
            title: 'No recurring activity detected yet',
            message:
                'PaisaTrack identifies subscriptions, EMIs, bills and regular income after three matching transactions are available.',
            actionLabel: 'Review transactions',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TransactionsScreen(),
              ),
            ),
          ),
        AsyncData(:final value) => ListView.separated(
            padding: AppSpacing.screen,
            itemCount: value.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => index == 0
                ? Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'Upcoming',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  )
                : _RecurringCard(
                    series: value[index - 1],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionsScreen(
                          initialMerchant: value[index - 1].label,
                        ),
                      ),
                    ),
                  ),
          ),
        AsyncError() => const ErrorStateView(
            message: 'Could not load recurring activity.',
          ),
        _ => const ListLoadingSkeleton(rows: 4),
      },
    );
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({required this.series, required this.onTap});

  final RecurringSery series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isIncome = series.kind == 'income';
    final amountColor = isIncome ? paisa.credit : paisa.debit;
    final date = MaterialLocalizations.of(context).formatMediumDate(
      series.nextExpectedDate.toLocal(),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KindIcon(kind: series.kind),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          series.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${_kindLabel(series.kind)} · ${_periodLabel(series.period)} · ${series.occurrences} payments',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${isIncome ? '+' : '-'}${formatInr(series.expectedAmount)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w600,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      series.status == 'missed'
                          ? 'Expected $date'
                          : 'Next expected $date',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (series.amountTrend == 'rising')
                    _StatusChip(
                      key: const ValueKey('price_creep_badge'),
                      label: 'Price rising',
                      icon: Icons.trending_up,
                      color: paisa.warning,
                    ),
                  if (series.amountTrend == 'rising' &&
                      series.status == 'missed')
                    const SizedBox(width: AppSpacing.xs),
                  if (series.status == 'missed')
                    _StatusChip(
                      key: const ValueKey('missed_badge'),
                      label: 'Missed',
                      icon: Icons.schedule,
                      color: paisa.warning,
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
      ),
      child: Icon(_kindIcon(kind), color: color, size: 20),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
      'emi' => 'EMI',
      'bill' => 'Bill',
      'recharge' => 'Recharge',
      'investment' => 'Investment',
      'income' => 'Income',
      _ => 'Subscription',
    };

IconData _kindIcon(String kind) => switch (kind) {
      'emi' => Icons.account_balance_outlined,
      'bill' => Icons.receipt_outlined,
      'recharge' => Icons.phone_android_outlined,
      'investment' => Icons.trending_up_outlined,
      'income' => Icons.savings_outlined,
      _ => Icons.subscriptions_outlined,
    };

String _periodLabel(String period) => switch (period) {
      'weekly' => 'Weekly',
      'monthly' => 'Monthly',
      'quarterly' => 'Quarterly',
      'yearly' => 'Yearly',
      _ => period,
    };
