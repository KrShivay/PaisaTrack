import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/db/database.dart' show Insight;
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../insights/insights_screen.dart';
import '../settings/app_settings.dart';
import 'dashboard_providers.dart';

/// Conic ring painter drawing category arcs in descending order with remainder arc.
class BloomHeroRingPainter extends CustomPainter {
  BloomHeroRingPainter({
    required this.slices,
    required this.isDark,
  });

  final List<CategorySlice> slices;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 25) / 2;
    const strokeWidth = 25.0;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = isDark
          ? AppColorTokens.bloomRingRemainderDark
          : AppColorTokens.bloomRingRemainderLight;

    // Draw full remainder background circle
    canvas.drawCircle(center, radius, backgroundPaint);

    if (slices.isEmpty) return;

    var startAngle = -math.pi / 2;
    for (final slice in slices) {
      if (slice.share <= 0) continue;
      final sweepAngle = 2 * math.pi * slice.share;
      final color = CategoryVisuals.color(slice.categoryId);

      final slicePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        slicePaint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant BloomHeroRingPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.isDark != isDark;
  }
}

/// 230px Hero Ring widget displaying category mix ring and inner 180px metric content.
class BloomHeroRing extends ConsumerWidget {
  const BloomHeroRing({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slices = ref.watch(categoryBreakdownProvider);
    final selectedMetric = ref.watch(selectedDashboardMetricProvider);
    final showPaise = ref.watch(showPaiseProvider);

    final safeToday = ref.watch(safeTodayValueProvider);
    final netFlow = ref.watch(monthNetProvider);
    final burn = ref.watch(dailyAverageSpendProvider);
    final runway = ref.watch(runwayValueProvider);

    final String labelText;
    final String amountText;
    final String subText;
    final Color? amountColor;

    switch (selectedMetric) {
      case DashboardMetricChoice.safeToday:
        labelText = 'SAFE TODAY';
        if (safeToday != null) {
          amountText = _formatAmount(safeToday, showPaise: showPaise);
          subText = safeToday >= 0 ? 'Budget on track' : 'Over daily budget';
          amountColor = safeToday >= 0
              ? (isDark
                  ? AppColorTokens.bloomCreditDark
                  : AppColorTokens.bloomCreditLight)
              : (isDark
                  ? AppColorTokens.bloomDebitDark
                  : AppColorTokens.bloomDebitLight);
        } else {
          amountText = 'No Budget';
          subText = 'Tap to set budget';
          amountColor = isDark
              ? AppColorTokens.bloomDarkTextSecondary
              : AppColorTokens.inkSecondary;
        }

      case DashboardMetricChoice.netFlow:
        labelText = 'NET FLOW';
        amountText = _formatAmount(netFlow, showPaise: showPaise);
        subText = netFlow >= 0 ? 'Surplus this month' : 'Deficit this month';
        amountColor = netFlow >= 0
            ? (isDark
                ? AppColorTokens.bloomCreditDark
                : AppColorTokens.bloomCreditLight)
            : (isDark
                ? AppColorTokens.bloomDebitDark
                : AppColorTokens.bloomDebitLight);

      case DashboardMetricChoice.burn:
        labelText = 'BURN RATE';
        amountText = _formatAmount(burn, showPaise: showPaise);
        subText = 'Per day average';
        amountColor =
            isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;

      case DashboardMetricChoice.runway:
        labelText = 'RUNWAY';
        if (runway != null) {
          amountText = '${runway.toStringAsFixed(0)} days';
          subText = 'At current burn rate';
        } else {
          amountText = '∞ days';
          subText = 'No active burn rate';
        }
        amountColor = AppColorTokens.bloomGold;
    }

    final innerBg =
        isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase;

    return Center(
      child: SizedBox(
        width: 230,
        height: 230,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(230, 230),
              painter: BloomHeroRingPainter(
                slices: slices,
                isDark: isDark,
              ),
            ),
            // Inner 180px circle
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: innerBg,
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.fast,
                child: KeyedSubtree(
                  key: ValueKey(selectedMetric),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          labelText,
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w600,
                            letterSpacing: 0.1,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextTertiary
                                : AppColorTokens.inkTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            amountText,
                            style: AppTheme.bloomMono(
                              38,
                              FontWeight.w600,
                              letterSpacing: -0.04,
                              color: amountColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subText,
                          style: AppTheme.bloomDisplay(
                            11,
                            FontWeight.w500,
                            color: isDark
                                ? AppColorTokens.bloomDarkTextSecondary
                                : AppColorTokens.inkSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double val, {required bool showPaise}) {
    var text = formatInr(val);
    if (!showPaise) {
      final idx = text.lastIndexOf('.');
      if (idx != -1) text = text.substring(0, idx);
    }
    return text;
  }
}

/// Helper provider reading showPaise setting
final showPaiseProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsControllerProvider).valueOrNull;
  return settings?.showPaise ?? true;
});

/// Row of 4 pills below the Hero Ring.
class BloomMetricSwitcherPills extends ConsumerWidget {
  const BloomMetricSwitcherPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDashboardMetricProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final choices = [
      (DashboardMetricChoice.safeToday, 'Safe today'),
      (DashboardMetricChoice.netFlow, 'Net flow'),
      (DashboardMetricChoice.burn, 'Burn'),
      (DashboardMetricChoice.runway, 'Runway'),
    ];

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (choice, label) in choices) ...[
            _MetricPillButton(
              label: label,
              isSelected: selected == choice,
              onTap: () {
                ref.read(selectedDashboardMetricProvider.notifier).state =
                    choice;
              },
              isDark: isDark,
            ),
            if (choice != choices.last.$1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _MetricPillButton extends StatelessWidget {
  const _MetricPillButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final activeBg = isDark ? AppColorTokens.violetPrimary : AppColorTokens.ink;
    final inactiveBg =
        isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomChip;
    const activeFg = Colors.white;
    final inactiveFg = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: isSelected ? activeBg : inactiveBg,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                label,
                style: AppTheme.bloomDisplay(
                  12,
                  isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? activeFg : inactiveFg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark emerald budget card from Pulse handoff.
class BloomBudgetCard extends ConsumerWidget {
  const BloomBudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(monthlyBudgetProvider).valueOrNull;
    final totals = ref.watch(monthDirectionTotalsProvider);
    final commitments = ref.watch(commitmentsTotalProvider);
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day;

    if (budget == null) {
      return _SetBudgetCard();
    }

    final spent = totals.debitTotal;
    final spentFraction = (spent / budget).clamp(0.0, 1.0);
    final committedFraction =
        (commitments / budget).clamp(0.0, 1.0 - spentFraction);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        gradient: AppColorTokens.bloomBudgetGradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Radial emerald glow top-right
          Positioned(
            right: -70,
            top: -50,
            child: Container(
              width: 190,
              height: 190,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x4D34D399),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Text(
                      '${_monthName(now.month).toUpperCase()} BUDGET',
                      style: AppTheme.bloomDisplay(
                        11,
                        FontWeight.w600,
                        letterSpacing: 0.14,
                        color: const Color(0xFF7FD9B6),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$daysLeft days left',
                        style: AppTheme.bloomMono(
                          10,
                          FontWeight.w500,
                          color: const Color(0xFF9DB2AB),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Amount row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatInr(spent),
                      style: AppTheme.bloomMono(
                        30,
                        FontWeight.w600,
                        letterSpacing: -0.04,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'of ${formatInr(budget)}',
                      style: AppTheme.bloomMono(
                        13,
                        FontWeight.w400,
                        color: const Color(0xFF9DB2AB),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Stacked 10px progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 10,
                    color: Colors.white.withValues(alpha: 0.08),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final totalW = constraints.maxWidth;
                        final spentW = totalW * spentFraction;
                        final committedW = totalW * committedFraction;

                        return Row(
                          children: [
                            if (spentW > 0)
                              Container(
                                width: spentW,
                                decoration: const BoxDecoration(
                                  gradient: AppColorTokens.bloomEmeraldGradient,
                                ),
                              ),
                            if (committedW > 0)
                              Container(
                                width: committedW,
                                color: AppColorTokens.bloomGold,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Caption
                Text(
                  '${formatInr(commitments)} of that is already committed to rent and EMIs — the gold slice.',
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: const Color(0xFFA9C4BB),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) => const [
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
      ][month - 1];
}

class _SetBudgetCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showBudgetInput(context, ref),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColorTokens.bloomCard,
          borderRadius: BorderRadius.circular(AppRadius.bloomCard),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 28,
              color: AppColorTokens.violetPrimary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set monthly budget',
                    style: AppTheme.bloomDisplay(14, FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unlocks safe-today calculation and progress ring.',
                    style: AppTheme.bloomDisplay(
                      12,
                      FontWeight.w400,
                      color: AppColorTokens.inkTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColorTokens.inkTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBudgetInput(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final amount = await showBloomDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Monthly Budget'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              prefixText: '₹ ',
              hintText: 'Enter amount',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter an amount';
              }
              final parsed = double.tryParse(value.trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter a positive number';
              }
              if (parsed > 10000000) {
                return 'Maximum ₹1 crore';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(double.parse(controller.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (amount == null) return;
    final repo = await ref.read(budgetRepositoryProvider.future);
    await repo.setMonthlyBudget(amount);
    ref.invalidate(monthlyBudgetProvider);
  }
}

/// "Where it went" top 3 categories section.
class BloomTopCategoriesSection extends ConsumerWidget {
  const BloomTopCategoriesSection({super.key, required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slices = ref.watch(categoryBreakdownProvider);
    final top3 = slices.take(3).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (top3.isEmpty) return const SizedBox.shrink();

    final maxVal = top3.first.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Where it went',
              style: AppTheme.bloomDisplay(
                16,
                FontWeight.w600,
                color: isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink,
              ),
            ),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'All →',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w600,
                  color: AppColorTokens.violetPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final slice in top3) ...[
          _CategoryRow(slice: slice, maxTotal: maxVal, isDark: isDark),
          if (slice != top3.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
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
          iconName: slice.icon,
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

/// Data-driven insight card that renders only persisted, evidence-backed insights.
///
/// Shows nothing when there are no active insights. Never displays fabricated
/// merchant names, amounts, or percentages.
class BloomInsightCard extends ConsumerWidget {
  const BloomInsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(activeInsightsProvider);
    final insights = insightsAsync.valueOrNull ?? const [];
    if (insights.isEmpty) return const SizedBox.shrink();

    final insight = insights.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _insightTitle(insight);
    final subtitle = _insightSubtitle(insight);

    if (title == null) return const SizedBox.shrink();

    final bg = isDark
        ? AppColorTokens.bloomGold.withValues(alpha: 0.14)
        : const Color(0xFFFFF3D8);
    final border = isDark
        ? AppColorTokens.bloomGold.withValues(alpha: 0.3)
        : const Color(0xFFF3D9A0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColorTokens.ink,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppColorTokens.bloomGold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFF3DFB4)
                        : const Color(0xFF3D2E06),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.bloomDisplay(
                      12,
                      FontWeight.w400,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : const Color(0xFF7E6A45),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _insightTitle(Insight insight) {
    switch (insight.kind) {
      case 'fees_total':
        return 'Fees & Charges Alert';
      case 'spike':
        return 'Spending Spike Detected';
      case 'trend_up':
        return 'Spending Trending Up';
      case 'trend_down':
        return 'Spending Trending Down';
      default:
        return null;
    }
  }

  String? _insightSubtitle(Insight insight) {
    switch (insight.kind) {
      case 'fees_total':
        return 'Review your fees for ${insight.period}';
      default:
        return 'Check your ${insight.period} spending patterns';
    }
  }
}

/// Today transaction list with unsorted indicator row.
class BloomTodayList extends ConsumerWidget {
  const BloomTodayList({super.key, required this.onTransactionTap});

  final ValueChanged<TransactionListItem> onTransactionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider);
    final reviewAttention = ref.watch(reviewAttentionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent',
              style: AppTheme.bloomDisplay(
                16,
                FontWeight.w600,
                color: isDark
                    ? AppColorTokens.bloomDarkTextPrimary
                    : AppColorTokens.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (reviewAttention != null && reviewAttention.count > 0) ...[
          _UnsortedRow(
            count: reviewAttention.count,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
        ],
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColorTokens.bloomDarkCard
                  : AppColorTokens.bloomCard,
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            child: Center(
              child: Text(
                'No transactions yet today',
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
          for (final txn in recent) ...[
            _TransactionRow(
              txn: txn,
              isDark: isDark,
              onTap: () => onTransactionTap(txn),
            ),
            if (txn != recent.last) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _UnsortedRow extends StatelessWidget {
  const _UnsortedRow({
    required this.count,
    required this.isDark,
  });

  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColorTokens.bloomWarningBg,
        borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        border:
            Border.all(color: AppColorTokens.bloomWarningBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF7E5BE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColorTokens.bloomWarningText,
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
                  'Unsorted transactions',
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w600,
                    color: AppColorTokens.bloomWarningText,
                  ),
                ),
                Text(
                  'Swipe to sort · $count left today',
                  style: AppTheme.bloomDisplay(
                    11,
                    FontWeight.w500,
                    color: AppColorTokens.bloomWarningText,
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

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.txn,
    required this.isDark,
    required this.onTap,
  });

  final TransactionListItem txn;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        ),
        child: Row(
          children: [
            BloomCategoryTile(
              categoryId: txn.categoryId,
              iconName: txn.categoryIcon,
              size: 36,
              borderRadius: 13,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.displayName,
                    style: AppTheme.bloomDisplay(
                      14,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(txn.ts),
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
            const SizedBox(width: 8),
            BloomAmount(
              amount: txn.direction == TransactionDirection.debit
                  ? -txn.amount
                  : txn.amount,
              size: 15,
              weight: FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final h =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final m = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'pm' : 'am';
    return '$h:$m $ampm';
  }
}
