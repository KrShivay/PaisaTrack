import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_state_views.dart';
import '../assistant/assistant_screen.dart';
import '../review/weekly_review_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transactions_screen.dart';
import 'dashboard_providers.dart';
import 'dashboard_widgets.dart';

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
    final totals = ref.watch(monthDirectionTotalsProvider);
    final net = ref.watch(monthNetProvider);
    final dailyAvg = ref.watch(dailyAverageSpendProvider);
    final projected = ref.watch(projectedMonthEndSpendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final trend = ref.watch(sixMonthTrendProvider);
    final reviewAttention = ref.watch(reviewAttentionProvider);
    final recent = ref.watch(recentTransactionsProvider);

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
          Text(
            _monthNames[now.month - 1],
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Monthly overview',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (hasActivity) ...[
            HeroFinancialCard(
              net: net,
              spent: totals.debitTotal,
              received: totals.creditTotal,
              monthComparison: mom,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TransactionsScreen(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            CompactMetricRow(
              dailyAverage: dailyAvg,
              monthComparison: mom,
              projectedSpend: projected,
            ),
          ] else
            EmptyStateView(
              illustration: AppIllustrations.wallet,
              title: 'No transactions this month',
              message:
                  'Transactions read from SMS or added manually will build your monthly overview here.',
              actionLabel: 'Add transaction',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TransactionsScreen(),
                ),
              ),
            ),
          if (reviewAttention != null) ...[
            const SizedBox(height: AppSpacing.md),
            ReviewAttentionCard(
              attention: reviewAttention,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WeeklyReviewScreen(),
                ),
              ),
            ),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            CategoryBreakdownCard(
              slices: categories,
              onSliceTap: (slice) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionsScreen(
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
                  builder: (_) => TransactionsScreen(
                    initialMerchant: merchant.name,
                  ),
                ),
              ),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            RecentTransactionsCard(
              transactions: recent,
              onTransactionTap: (id) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionDetailScreen(txnId: id),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TrendSparkline(points: trend),
        ],
      ),
    );
  }
}
