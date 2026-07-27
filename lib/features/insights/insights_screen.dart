import 'dart:convert';
import 'package:drift/drift.dart' show Expression, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../dashboard/dashboard_providers.dart';
import '../dashboard/period_selection_sheet.dart';
import '../recurring/recurring_screen.dart';

/// Stream of non-dismissed precomputed insights for the current period.
final activeInsightsProvider = StreamProvider<List<Insight>>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final period = ref.watch(dashboardPeriodProvider);
  final monthKey =
      '${period.start.year}-${period.start.month.toString().padLeft(2, '0')}';

  return dbAsync.when(
    data: (db) => (db.select(db.insights)
          ..where(
            (i) => Expression.and([
              i.period.equals(monthKey),
              i.dismissed.equals(false),
            ]),
          ))
        .watch(),
    loading: () => const Stream<List<Insight>>.empty(),
    error: (err, st) => Stream<List<Insight>>.error(err, st),
  );
});

/// Redesigned Bloom Trends (Insights) screen with scoped period picker,
/// narrative insight cards with dismissal, 6-month bar chart, MoM comparison,
/// category share breakdown, and top merchants.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final period = ref.watch(dashboardPeriodProvider);
    final sixMonthTrend = ref.watch(sixMonthTrendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final totals = ref.watch(monthDirectionTotalsProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);
    final activeInsightsAsync = ref.watch(activeInsightsProvider);
    final insights = activeInsightsAsync.valueOrNull ?? const [];

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Top Header: Title + Period Chip + Recurring button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trends',
                        style: AppTheme.bloomDisplay(
                          22,
                          FontWeight.w700,
                          letterSpacing: -0.03,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Spending patterns & analytics',
                        style: AppTheme.bloomDisplay(
                          12,
                          FontWeight.w400,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextTertiary
                              : AppColorTokens.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    showBloomModalSheet(
                      context: context,
                      builder: (context) => const BloomDatePeriodSheet(),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomChip,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextSecondary
                              : AppColorTokens.inkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          period.label,
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w600,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextSecondary
                                : AppColorTokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecurringScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColorTokens.bloomDarkCard
                          : AppColorTokens.bloomChip,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.autorenew_rounded,
                          size: 14,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextSecondary
                              : AppColorTokens.inkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Recurring',
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w600,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextSecondary
                                : AppColorTokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Narrative Insights Cards (if any non-dismissed)
            if (insights.isNotEmpty) ...[
              for (final insight in insights) ...[
                _NarrativeInsightCard(
                  insight: insight,
                  isDark: isDark,
                  onDismiss: () async {
                    final db = await ref.read(appDatabaseProvider.future);
                    await (db.update(db.insights)
                          ..where((row) => row.id.equals(insight.id)))
                        .write(const InsightsCompanion(dismissed: Value(true)));
                  },
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
            ],

            // 6-Month Spend Bar Chart Card
            _SixMonthBarChartCard(
              trend: sixMonthTrend,
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // Month-over-Month Comparison Card
            _MoMComparisonCard(
              mom: mom,
              currentSpend: totals.debitTotal,
              isDark: isDark,
            ),
            const SizedBox(height: 24),

            // Category Breakdown Section
            _CategoryBreakdownSection(
              categories: categories,
              isDark: isDark,
            ),
            const SizedBox(height: 24),

            // Top Merchants Section
            _TopMerchantsSection(
              merchants: merchants,
              isDark: isDark,
            ),

            // Bottom clearance for floating nav pill
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }
}

class _NarrativeInsightCard extends StatelessWidget {
  const _NarrativeInsightCard({
    required this.insight,
    required this.isDark,
    required this.onDismiss,
  });

  final Insight insight;
  final bool isDark;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? AppColorTokens.violetPrimary.withValues(alpha: 0.16)
        : const Color(0xFFF3E8FF);
    final border = isDark
        ? AppColorTokens.violetPrimary.withValues(alpha: 0.3)
        : const Color(0xFFE9D5FF);

    final spec = _parseInsight(insight);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            spec.icon,
            size: 20,
            color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7E22CE),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.body,
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : AppColorTokens.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
        ],
      ),
    );
  }

  _InsightDisplaySpec _parseInsight(Insight insight) {
    try {
      final payload = jsonDecode(insight.payloadJson) as Map<String, dynamic>;
      switch (insight.kind) {
        case 'fees_total':
          final total = (payload['total'] as num?)?.toDouble() ?? 0.0;
          return _InsightDisplaySpec(
            title: 'Fees & Charges Alert',
            body:
                'You spent ${formatInr(total)} in fees this month. Check subscription renewal details.',
            icon: Icons.account_balance_wallet_outlined,
          );
        case 'category_delta':
          final category = payload['category_name'] ?? 'category';
          final delta = (payload['delta_fraction'] as num?)?.toDouble() ?? 0.0;
          final pct = (delta.abs() * 100).toStringAsFixed(0);
          final direction = delta > 0 ? 'increased' : 'decreased';
          return _InsightDisplaySpec(
            title: 'Category Shift',
            body:
                '$category spending $direction by $pct% compared to last month.',
            icon: Icons.trending_up_rounded,
          );
        case 'duplicate_subscription':
          final label = payload['label'] ?? 'Service';
          return _InsightDisplaySpec(
            title: 'Duplicate Subscription',
            body: 'Multiple active subscriptions detected for $label.',
            icon: Icons.copy_rounded,
          );
        case 'price_creep':
          final label = payload['label'] ?? 'Service';
          return _InsightDisplaySpec(
            title: 'Price Creep Detected',
            body: 'Amount for $label has increased in recent billing cycles.',
            icon: Icons.show_chart_rounded,
          );
        default:
          return const _InsightDisplaySpec(
            title: 'Smart Insight',
            body: 'Pattern detected in your transaction history.',
            icon: Icons.lightbulb_outline_rounded,
          );
      }
    } catch (_) {
      return const _InsightDisplaySpec(
        title: 'Smart Insight',
        body: 'Pattern detected in your transaction history.',
        icon: Icons.lightbulb_outline_rounded,
      );
    }
  }
}

class _InsightDisplaySpec {
  const _InsightDisplaySpec({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}

class _SixMonthBarChartCard extends StatelessWidget {
  const _SixMonthBarChartCard({
    required this.trend,
    required this.isDark,
  });

  final List<MonthPoint> trend;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final maxSpend = trend.fold<double>(
      1.0,
      (max, b) => b.spend > max ? b.spend : max,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPEND TREND (LAST 6 MONTHS)',
            style: AppTheme.bloomDisplay(
              11,
              FontWeight.w600,
              letterSpacing: 0.1,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < trend.length; i++) ...[
                  _BarColumn(
                    bucket: trend[i],
                    isCurrent: i == trend.length - 1,
                    maxSpend: maxSpend,
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.bucket,
    required this.isCurrent,
    required this.maxSpend,
    required this.isDark,
  });

  final MonthPoint bucket;
  final bool isCurrent;
  final double maxSpend;
  final bool isDark;

  static const _monthAbbrev = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final heightFactor = (bucket.spend / maxSpend).clamp(0.06, 1.0);
    final activeColor =
        isDark ? AppColorTokens.violetPrimary : AppColorTokens.ink;
    final inactiveColor = isDark
        ? AppColorTokens.bloomDarkTextTertiary.withValues(alpha: 0.3)
        : AppColorTokens.bloomChip;

    final monthLabel = _monthAbbrev[bucket.month.month - 1];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          bucket.spend > 0 ? formatInrCompact(bucket.spend) : '',
          style: AppTheme.bloomMono(
            9,
            FontWeight.w500,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 24,
          height: 80 * heightFactor,
          decoration: BoxDecoration(
            color: isCurrent ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          monthLabel,
          style: AppTheme.bloomDisplay(
            11,
            isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent
                ? (isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink)
                : (isDark
                    ? AppColorTokens.bloomDarkTextTertiary
                    : AppColorTokens.inkTertiary),
          ),
        ),
      ],
    );
  }
}

class _MoMComparisonCard extends StatelessWidget {
  const _MoMComparisonCard({
    required this.mom,
    required this.currentSpend,
    required this.isDark,
  });

  final MonthOverMonthSpend mom;
  final double currentSpend;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final pctChange = mom.pctChange ?? 0.0;
    final isIncrease = pctChange > 0;
    final isZero = pctChange == 0;

    final badgeBg = isZero
        ? (isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip)
        : isIncrease
            ? (isDark
                ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
                : const Color(0xFFFFF0D6))
            : (isDark
                ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
                : const Color(0xFFD3F2E4));

    final badgeColor = isZero
        ? (isDark
            ? AppColorTokens.bloomDarkTextSecondary
            : AppColorTokens.inkSecondary)
        : isIncrease
            ? AppColorTokens.bloomGold
            : AppColorTokens.bloomEmerald;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONTH OVER MONTH',
                  style: AppTheme.bloomDisplay(
                    11,
                    FontWeight.w600,
                    letterSpacing: 0.1,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatInr(currentSpend),
                  style: AppTheme.bloomMono(
                    26,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatInr(currentSpend)} spent so far vs ${formatInr(mom.previous)} last month',
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextTertiary
                        : AppColorTokens.inkTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isIncrease
                      ? Icons.arrow_upward_rounded
                      : isZero
                          ? Icons.remove_rounded
                          : Icons.arrow_downward_rounded,
                  size: 14,
                  color: badgeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${pctChange.abs().toStringAsFixed(1)}%',
                  style: AppTheme.bloomMono(
                    13,
                    FontWeight.w600,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownSection extends StatelessWidget {
  const _CategoryBreakdownSection({
    required this.categories,
    required this.isDark,
  });

  final List<CategorySlice> categories;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SPENDING BY CATEGORY',
          style: AppTheme.bloomDisplay(
            11,
            FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Center(
              child: Text(
                'No category data for this period',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Column(
              children: [
                for (final cat in categories) ...[
                  Row(
                    children: [
                      BloomCategoryTile(
                        categoryId: cat.categoryId,
                        iconName: cat.icon,
                        size: 32,
                        borderRadius: 11,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  cat.name,
                                  style: AppTheme.bloomDisplay(
                                    13,
                                    FontWeight.w500,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                                Text(
                                  formatInr(cat.total),
                                  style: AppTheme.bloomMono(
                                    13,
                                    FontWeight.w500,
                                    color: isDark
                                        ? AppColorTokens.bloomDarkTextPrimary
                                        : AppColorTokens.ink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: cat.share.clamp(0.0, 1.0),
                              backgroundColor: isDark
                                  ? AppColorTokens.bloomDarkOutline
                                  : AppColorTokens.bloomChip,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CategoryVisuals.color(cat.categoryId),
                              ),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (cat != categories.last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TopMerchantsSection extends StatelessWidget {
  const _TopMerchantsSection({
    required this.merchants,
    required this.isDark,
  });

  final List<MerchantStat> merchants;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOP MERCHANTS',
          style: AppTheme.bloomDisplay(
            11,
            FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark
                ? AppColorTokens.bloomDarkTextTertiary
                : AppColorTokens.inkTertiary,
          ),
        ),
        const SizedBox(height: 12),
        if (merchants.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Center(
              child: Text(
                'No merchant data for this period',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w400,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextSecondary
                      : AppColorTokens.inkSecondary,
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Column(
              children: [
                for (final merchant in merchants) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          merchant.name,
                          style: AppTheme.bloomDisplay(
                            13,
                            FontWeight.w500,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextPrimary
                                : AppColorTokens.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatInr(merchant.total),
                        style: AppTheme.bloomMono(
                          13,
                          FontWeight.w500,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                    ],
                  ),
                  if (merchant != merchants.last) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
