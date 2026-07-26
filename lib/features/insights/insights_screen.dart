import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../dashboard/dashboard_providers.dart';
import '../recurring/recurring_screen.dart';

/// Redesigned Bloom Trends (Insights) screen with 6-month bar chart, MoM comparison,
/// category share breakdown, and top merchants.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sixMonthTrend = ref.watch(sixMonthTrendProvider);
    final mom = ref.watch(monthOverMonthSpendProvider);
    final totals = ref.watch(monthDirectionTotalsProvider);
    final categories = ref.watch(categoryBreakdownProvider);
    final merchants = ref.watch(topMerchantsProvider);

    return Scaffold(
      backgroundColor:
          isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Top Header: Title + Recurring button
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
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecurringScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                          size: 16,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextSecondary
                              : AppColorTokens.inkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Recurring',
                          style: AppTheme.bloomDisplay(
                            12,
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
            const SizedBox(height: 24),

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

  @override
  Widget build(BuildContext context) {
    final fraction = (bucket.spend / maxSpend).clamp(0.06, 1.0);
    final barHeight = 90.0 * fraction;

    final activeColor =
        isDark ? AppColorTokens.violetPrimary : AppColorTokens.ink;
    final inactiveColor =
        isDark ? const Color(0xFF292448) : const Color(0xFFE7E4F5);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isCurrent && bucket.spend > 0)
          Text(
            _formatCompact(bucket.spend),
            style: AppTheme.bloomMono(
              10,
              FontWeight.w600,
              color: activeColor,
            ),
          )
        else
          const SizedBox(height: 14),
        const SizedBox(height: 4),
        Container(
          width: 28,
          height: barHeight,
          decoration: BoxDecoration(
            color: isCurrent ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _shortMonth(bucket.month.month),
          style: AppTheme.bloomDisplay(
            11,
            isCurrent ? FontWeight.w600 : FontWeight.w500,
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

  String _shortMonth(int month) => const [
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
      ][month - 1];

  String _formatCompact(double val) {
    if (val >= 1000) {
      return '₹${(val / 1000).toStringAsFixed(1)}k';
    }
    return '₹${val.toStringAsFixed(0)}';
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
    final pct = mom.pctChange;

    final isLowerSpend = pct != null && pct <= 0;
    final chipBg = isLowerSpend
        ? (isDark
            ? AppColorTokens.bloomEmerald.withValues(alpha: 0.18)
            : const Color(0xFFD3F2E4))
        : (isDark
            ? AppColorTokens.bloomDebitDark.withValues(alpha: 0.18)
            : const Color(0xFFFDE8E8));
    final chipFg = isLowerSpend
        ? (isDark ? AppColorTokens.bloomCreditDark : const Color(0xFF0E9F6E))
        : (isDark
            ? AppColorTokens.bloomDebitDark
            : AppColorTokens.bloomDebitLight);

    final chipText = pct != null
        ? '${pct <= 0 ? "↓" : "↑"} ${pct.abs().toStringAsFixed(0)}% vs last month'
        : 'First month tracked';

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
                const SizedBox(height: 6),
                Text(
                  '${formatInr(currentSpend)} spent so far',
                  style: AppTheme.bloomDisplay(
                    15,
                    FontWeight.w600,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextPrimary
                        : AppColorTokens.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'vs ${formatInr(mom.previous)} same time last month',
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chipText,
                style: AppTheme.bloomDisplay(
                  11,
                  FontWeight.w600,
                  color: chipFg,
                ),
              ),
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
    if (categories.isEmpty) return const SizedBox.shrink();
    final maxTotal = categories.first.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: AppTheme.bloomDisplay(
            16,
            FontWeight.w600,
            color: isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
        ),
        const SizedBox(height: 12),
        for (final slice in categories) ...[
          _CategoryItemRow(slice: slice, maxTotal: maxTotal, isDark: isDark),
          if (slice != categories.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CategoryItemRow extends StatelessWidget {
  const _CategoryItemRow({
    required this.slice,
    required this.maxTotal,
    required this.isDark,
  });

  final CategorySlice slice;
  final double maxTotal;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final barFraction =
        maxTotal > 0 ? (slice.total / maxTotal).clamp(0.05, 1.0) : 0.0;
    final color = CategoryVisuals.color(slice.categoryId);

    return Row(
      children: [
        BloomCategoryTile(
          categoryId: slice.categoryId,
          size: 36,
          borderRadius: 13,
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
                    slice.name,
                    style: AppTheme.bloomDisplay(
                      13,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  ),
                  Text(
                    formatInr(slice.total),
                    style: AppTheme.bloomMono(
                      13,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : AppColorTokens.inkSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  height: 6,
                  color: isDark
                      ? AppColorTokens.bloomDarkTrack
                      : AppColorTokens.bloomChip,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: barFraction,
                    child: Container(color: color),
                  ),
                ),
              ),
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
    if (merchants.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Merchants',
          style: AppTheme.bloomDisplay(
            16,
            FontWeight.w600,
            color: isDark
                ? AppColorTokens.bloomDarkTextPrimary
                : AppColorTokens.ink,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in merchants) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColorTokens.bloomDarkCard
                  : AppColorTokens.bloomCard,
              borderRadius: BorderRadius.circular(AppRadius.bloomRow),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColorTokens.bloomDarkTrack
                        : AppColorTokens.bloomChip,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(
                      item.name.substring(0, 1).toUpperCase(),
                      style: AppTheme.bloomDisplay(
                        14,
                        FontWeight.w700,
                        color: AppColorTokens.violetPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: AppTheme.bloomDisplay(
                          14,
                          FontWeight.w500,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.count} payments',
                        style: AppTheme.bloomDisplay(
                          11,
                          FontWeight.w400,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextTertiary
                              : AppColorTokens.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                BloomAmount(
                  amount: -item.total,
                  size: 15,
                  weight: FontWeight.w500,
                ),
              ],
            ),
          ),
          if (item != merchants.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}
