import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/paisa_colors.dart';
import '../assistant/assistant_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transactions_screen.dart';
import 'dashboard_providers.dart';
import 'dashboard_widgets.dart';

/// Month-summary dashboard: totals plus derived stats (net flow, pace,
/// month-over-month, category breakdown, top merchants, and a spend trend).
///
/// Styling follows docs/design-system.md: semantic money colors come from
/// [PaisaColors], amounts render with tabular figures, and spacing/radius use
/// the token scale. All stats are derived in memory from the loaded
/// transaction list (see dashboard_providers.dart) — no extra DB queries.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);

    final totals = ref.watch(monthDirectionTotalsProvider);
    final net = ref.watch(monthNetProvider);
    final dailyAvg = ref.watch(dailyAverageSpendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final trend = ref.watch(sixMonthTrendProvider);

    final now = DateTime.now();
    final hasActivity = totals.debitTotal > 0 || totals.creditTotal > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Ask PaisaTrack',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AssistantScreen(),
              ),
            ),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          // Month header with net-flow chip. The month name flexes (and
          // ellipsizes) so a wide net amount can't push the chip off-screen.
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthNames[now.month - 1],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: NetFlowChip(net: net)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Two-up summary row.
          Row(
            children: [
              Expanded(
                child: SummaryCard(
                  label: 'Spent',
                  amount: totals.debitTotal,
                  color: paisa.debit,
                  icon: Icons.arrow_outward,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SummaryCard(
                  label: 'Received',
                  amount: totals.creditTotal,
                  color: paisa.credit,
                  icon: Icons.arrow_downward,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Net / pace strip. IntrinsicHeight gives the row a bounded height so
          // CrossAxisAlignment.stretch can equalize the three tiles; without it
          // stretch inside this ListView demands infinite height.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Net this month',
                    value: '${net >= 0 ? '+' : '−'}${formatInr(net.abs())}',
                    accent: net >= 0 ? paisa.credit : paisa.debit,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: StatTile(
                    label: 'Daily average',
                    value: formatInr(dailyAvg),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _MoMTile(mom: mom),
                ),
              ],
            ),
          ),

          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CategoryBreakdownCard(
              slices: categories,
              onSliceTap: (slice) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => TransactionsScreen(
                    initialCategoryId: slice.categoryId,
                    initialCategoryName: slice.name,
                  ),
                ),
              ),
            ),
          ],

          if (merchants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            TopMerchantsCard(
              merchants: merchants,
              onMerchantTap: (merchant) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      TransactionsScreen(initialMerchant: merchant.name),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          TrendSparkline(points: trend),

          if (!hasActivity) ...[
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Text(
                'No transactions yet this month.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Month-over-month spend tile: shows the percent change with a direction
/// arrow. Rising spend uses the debit hue, falling spend the credit hue —
/// applied to the small indicator only, per design-system.md §5.
class _MoMTile extends StatelessWidget {
  const _MoMTile({required this.mom});

  final MonthOverMonthSpend mom;

  @override
  Widget build(BuildContext context) {
    final paisa = PaisaColors.of(context);
    final pct = mom.pctChange;

    if (pct == null) {
      return const StatTile(label: 'vs last month', value: '—');
    }

    final rising = pct > 0;
    final flat = pct.abs() < 0.005;
    final color = flat
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : (rising ? paisa.debit : paisa.credit);
    final icon = flat
        ? Icons.trending_flat
        : (rising ? Icons.arrow_upward : Icons.arrow_downward);
    final pctText = '${(pct.abs() * 100).round()}%';

    return StatTile(
      label: 'vs last month',
      value: pctText,
      accent: color,
      trailing: Icon(icon, size: 16, color: color),
    );
  }
}
