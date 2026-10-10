import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../intelligence/claim.dart';
import '../insights/insights_screen.dart';
import '../settings/app_settings.dart';
import '../transactions/transactions_screen.dart';
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
  const BloomHeroRing({super.key, this.size = 230});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slices = ref.watch(categoryBreakdownProvider).valueOrNull ?? const [];
    final selectedMetric = ref.watch(selectedDashboardMetricProvider);
    final showPaise = ref.watch(showPaiseProvider);

    final creditColor = isDark
        ? AppColorTokens.bloomCreditDark
        : AppColorTokens.bloomCreditLight;
    final debitColor =
        isDark ? AppColorTokens.bloomDebitDark : AppColorTokens.bloomDebitLight;
    final secondaryColor = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    final primaryColor =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;

    // Resolve the selected metric into displayable content while keeping the
    // aggregate's loading and error states distinct — the ring never shows a
    // fabricated number sourced from the bounded transaction feed (PV-02).
    final AsyncValue<_HeroMetricContent> contentAsync;
    switch (selectedMetric) {
      case DashboardMetricChoice.safeToday:
        contentAsync = ref.watch(budgetStatusProvider).whenData(
              (status) => status == null
                  ? _HeroMetricContent(
                      label: 'SAFE TODAY',
                      amount: 'No Budget',
                      sub: 'Tap to set budget',
                      color: secondaryColor,
                    )
                  : _HeroMetricContent(
                      label: 'SAFE TODAY',
                      amount: _formatAmount(
                        status.safePerDay,
                        showPaise: showPaise,
                      ),
                      sub: status.isOver
                          ? 'Budget used up · ${formatInr(-status.left)} short '
                              'incl. bills'
                          : '${formatInr(status.left)} left · '
                              '${status.daysRemaining} days',
                      color: status.isOver ? debitColor : creditColor,
                    ),
            );
      case DashboardMetricChoice.netFlow:
        contentAsync = ref.watch(monthDirectionTotalsProvider).whenData(
          (totals) {
            final netFlow = totals.creditTotal - totals.debitTotal;
            return _HeroMetricContent(
              label: 'NET FLOW',
              amount: _formatAmount(netFlow, showPaise: showPaise),
              sub: 'In ${formatInr(totals.creditTotal)} · '
                  'Out ${formatInr(totals.debitTotal)}',
              color: netFlow >= 0 ? creditColor : debitColor,
            );
          },
        );
      case DashboardMetricChoice.burn:
        contentAsync = ref.watch(dailyAverageSpendProvider).whenData(
              (burn) => _HeroMetricContent(
                label: 'BURN RATE',
                amount: _formatAmount(burn, showPaise: showPaise),
                sub: 'Per day average',
                color: primaryColor,
              ),
            );
      case DashboardMetricChoice.runway:
        contentAsync = ref.watch(runwayValueProvider).whenData(
              (runway) => _HeroMetricContent(
                label: 'RUNWAY',
                amount: runway != null
                    ? '${runway.toStringAsFixed(0)} days'
                    : '∞ days',
                sub: runway != null
                    ? 'At current burn rate'
                    : 'No active burn rate',
                color: AppColorTokens.bloomGold,
              ),
            );
    }

    final innerBg =
        isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase;
    final compact = size < 200;
    final innerSize = size * 0.78;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: BloomHeroRingPainter(
                slices: slices,
                isDark: isDark,
              ),
            ),
            // Keep the inner circle proportional when the landscape ring shrinks.
            Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: innerBg,
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.fast,
                child: KeyedSubtree(
                  key: ValueKey('$selectedMetric-${contentAsync.runtimeType}'),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 3 : 12),
                    child: contentAsync.when(
                      data: (content) => _heroInner(
                        label: content.label,
                        amount: content.amount,
                        sub: content.sub,
                        amountColor: content.color,
                        isDark: isDark,
                        compact: compact,
                      ),
                      loading: () => _heroInner(
                        label: _metricLabel(selectedMetric),
                        amountWidget: const SizedBox(
                          width: 96,
                          child: BloomSkeleton(height: 34, borderRadius: 10),
                        ),
                        sub: 'Updating…',
                        isDark: isDark,
                        compact: compact,
                      ),
                      error: (_, __) => _heroInner(
                        label: _metricLabel(selectedMetric),
                        amount: '—',
                        amountColor: secondaryColor,
                        sub: 'Unavailable',
                        isDark: isDark,
                        compact: compact,
                      ),
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

  static String _metricLabel(DashboardMetricChoice metric) => switch (metric) {
        DashboardMetricChoice.safeToday => 'SAFE TODAY',
        DashboardMetricChoice.netFlow => 'NET FLOW',
        DashboardMetricChoice.burn => 'BURN RATE',
        DashboardMetricChoice.runway => 'RUNWAY',
      };

  Widget _heroInner({
    required String label,
    required String sub,
    required bool isDark,
    bool compact = false,
    String? amount,
    Widget? amountWidget,
    Color? amountColor,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: AppTheme.bloomDisplay(
              compact ? 10 : 11,
              FontWeight.w600,
              letterSpacing: 0.1,
              color: isDark
                  ? AppColorTokens.bloomDarkTextTertiary
                  : AppColorTokens.inkTertiary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        amountWidget ??
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount ?? '',
                style: AppTheme.bloomMono(
                  compact ? 34 : 38,
                  FontWeight.w600,
                  letterSpacing: -0.04,
                  color: amountColor,
                ),
              ),
            ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            sub,
            maxLines: 1,
            softWrap: false,
            style: AppTheme.bloomDisplay(
              compact ? 10 : 11,
              FontWeight.w500,
              color: isDark
                  ? AppColorTokens.bloomDarkTextSecondary
                  : AppColorTokens.inkSecondary,
            ),
          ),
        ),
      ],
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

class _HeroMetricContent {
  const _HeroMetricContent({
    required this.label,
    required this.amount,
    required this.sub,
    required this.color,
  });

  final String label;
  final String amount;
  final String sub;
  final Color? color;
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

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final (choice, label) in choices) ...[
          _MetricPillButton(
            label: label,
            isSelected: selected == choice,
            onTap: () {
              ref.read(selectedDashboardMetricProvider.notifier).state = choice;
            },
            isDark: isDark,
          ),
        ],
      ],
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
      container: true,
      label: label,
      button: true,
      selected: isSelected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? activeBg : inactiveBg,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  widthFactor: 1,
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
        ),
      ),
    );
  }
}

/// Explains the period, spending eligibility, known exclusions, and data
/// coverage behind dashboard totals. Numeric exclusion details are shown only
/// after a successful aggregate, so loading and error never resemble zero.
class BloomExclusionsNote extends ConsumerWidget {
  const BloomExclusionsNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aggregate = ref.watch(dashboardAggregateProvider);
    final exclusions = ref.watch(dashboardExclusionsProvider).valueOrNull;
    final period = ref.watch(dashboardPeriodProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showPaise = ref.watch(showPaiseProvider);
    final primary =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    final surface =
        isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final outline =
        isDark ? AppColorTokens.bloomDarkOutline : AppColorTokens.bloomHairline;
    String? aggregateStatus;
    if (aggregate.isLoading) {
      aggregateStatus = 'Updating totals for this period…';
    } else if (aggregate.hasError) {
      aggregateStatus =
          'Totals are unavailable while transaction data could not be loaded.';
    }

    var excludedAmount =
        exclusions == null ? null : formatInr(exclusions.total);
    if (excludedAmount != null && !showPaise) {
      final idx = excludedAmount.lastIndexOf('.');
      if (idx != -1) excludedAmount = excludedAmount.substring(0, idx);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: secondary),
              const SizedBox(width: 6),
              Text(
                'About these totals',
                style:
                    AppTheme.bloomDisplay(12, FontWeight.w600, color: primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Period: ${period.label}',
            style: AppTheme.bloomDisplay(11, FontWeight.w600, color: primary),
          ),
          const SizedBox(height: 4),
          Text(
            'Spending counts settled debit transactions in spending categories. '
            'Transactions without a category count as spending unless another rule excludes them.',
            style: AppTheme.bloomDisplay(11, FontWeight.w400, color: secondary),
          ),
          const SizedBox(height: 4),
          Text(
            'For spending, pending, reversed or failed transactions, deleted or '
            'duplicate rows, owned transfers, non-spending categories, and transactions '
            'excluded from analytics are left out. Credit totals count settled credits '
            'except deleted, duplicate, owned-transfer, or excluded-source rows.',
            style: AppTheme.bloomDisplay(11, FontWeight.w400, color: secondary),
          ),
          const SizedBox(height: 4),
          Text(
            'These totals include only activity recorded in PaisaTrack; missing or unrecorded transactions are not visible here.',
            style: AppTheme.bloomDisplay(11, FontWeight.w400, color: secondary),
          ),
          if (aggregateStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              aggregateStatus,
              style:
                  AppTheme.bloomDisplay(11, FontWeight.w600, color: secondary),
            ),
          ] else if (exclusions != null &&
              exclusions.total > 0 &&
              excludedAmount != null) ...[
            const SizedBox(height: 6),
            Text(
              'Owned transfers and transactions excluded from analytics: '
              '$excludedAmount across ${exclusions.count} settled spending '
              '${exclusions.count == 1 ? 'debit' : 'debits'} not counted.',
              style:
                  AppTheme.bloomDisplay(11, FontWeight.w600, color: secondary),
            ),
          ],
        ],
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
    final totalsAsync = ref.watch(monthDirectionTotalsProvider);
    final commitments = ref.watch(commitmentsTotalProvider);

    if (budget == null) {
      return _SetBudgetCard();
    }

    // Spent comes only from the SQL aggregate. While it loads or fails we show
    // the card chrome without a fabricated spent figure (PV-02).
    return totalsAsync.when(
      data: (totals) => _card(
        budget: budget,
        spent: totals.debitTotal,
        commitments: commitments,
      ),
      loading: () => _card(
        budget: budget,
        spent: null,
        commitments: commitments,
      ),
      error: (_, __) => _card(
        budget: budget,
        spent: null,
        commitments: commitments,
        isError: true,
      ),
    );
  }

  Widget _card({
    required double budget,
    required double? spent,
    required double commitments,
    bool isError = false,
  }) {
    final now = DateTime.now();
    final daysLeft = daysRemainingInMonth(now);

    final spentFraction =
        spent == null ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final committedFraction = spent == null
        ? 0.0
        : (commitments / budget).clamp(0.0, 1.0 - spentFraction);
    final spentAmount = spent != null
        ? Text(
            formatInr(spent),
            style: AppTheme.bloomMono(
              30,
              FontWeight.w600,
              letterSpacing: -0.04,
              color: Colors.white,
            ),
          )
        : isError
            ? Text(
                '—',
                style: AppTheme.bloomMono(
                  30,
                  FontWeight.w600,
                  letterSpacing: -0.04,
                  color: Colors.white,
                ),
              )
            : const SizedBox(
                width: 120,
                child: BloomSkeleton(height: 28, borderRadius: 8),
              );
    final overspent = spent != null && spent > budget;
    final budgetAmount = Text(
      'spent of ${formatInr(budget)}',
      style: AppTheme.bloomMono(
        13,
        FontWeight.w400,
        color: const Color(0xFF9DB2AB),
      ),
    );

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
                // Stack metadata on compact cards instead of squeezing it
                // beside a large-text month label.
                LayoutBuilder(
                  builder: (context, constraints) {
                    final month = Text(
                      '${_monthName(now.month).toUpperCase()} BUDGET',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bloomDisplay(
                        11,
                        FontWeight.w600,
                        letterSpacing: 0.14,
                        color: const Color(0xFF7FD9B6),
                      ),
                    );
                    final days = Container(
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
                    );
                    if (constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [month, const SizedBox(height: 8), days],
                      );
                    }
                    return Row(
                      children: [month, const Spacer(), days],
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Keep both complete amounts readable at compact widths.
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          spentAmount,
                          const SizedBox(height: 4),
                          budgetAmount,
                        ],
                      );
                    }
                    // Wrap (not Row): large lakh amounts plus the "spent of"
                    // label move to a second line instead of overflowing.
                    return Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [spentAmount, budgetAmount],
                    );
                  },
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
                                decoration: BoxDecoration(
                                  gradient: overspent
                                      ? null
                                      : AppColorTokens.bloomEmeraldGradient,
                                  color: overspent
                                      ? AppColorTokens.bloomDebitDark
                                      : null,
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
                  isError
                      ? 'Spending total is unavailable right now.'
                      : _budgetCaption(
                          budget: budget,
                          spent: spent,
                          commitments: commitments,
                        ),
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

  /// Caption that makes budget − spent − bills = left add up on the card.
  String _budgetCaption({
    required double budget,
    required double? spent,
    required double commitments,
  }) {
    final bills = commitments > 0
        ? '${formatInr(commitments)} recurring bills still expected (gold).'
        : 'No more recurring bills expected this month.';
    if (spent == null) return bills;
    final left = budget - spent - commitments;
    if (spent > budget) {
      return '${formatInr(spent - budget)} over budget. $bills';
    }
    return left >= 0
        ? '${formatInr(left)} left after bills. $bills'
        : 'Bills exceed what is left by ${formatInr(-left)}. $bills';
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
    void openBudget() => _showBudgetInput(context, ref);

    return Semantics(
      container: true,
      label:
          'Set monthly budget. Unlocks safe-today calculation and progress ring.',
      button: true,
      onTap: openBudget,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openBudget,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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
          ),
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
    final slicesAsync = ref.watch(categoryBreakdownProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return slicesAsync.when(
      data: (slices) {
        final top3 = slices.take(3).toList();
        if (top3.isEmpty) return const SizedBox.shrink();
        final maxVal = top3.first.total;
        return _wrap(
          isDark,
          [
            for (final slice in top3) ...[
              _CategoryRow(slice: slice, maxTotal: maxVal, isDark: isDark),
              if (slice != top3.last) const SizedBox(height: 10),
            ],
          ],
        );
      },
      loading: () => _wrap(
        isDark,
        const [
          BloomSkeleton(height: 18),
          SizedBox(height: 10),
          BloomSkeleton(height: 18),
          SizedBox(height: 10),
          BloomSkeleton(height: 18),
        ],
      ),
      error: (_, __) => _wrap(
        isDark,
        [
          Text(
            "Couldn't load category breakdown.",
            style: AppTheme.bloomDisplay(
              13,
              FontWeight.w400,
              color: isDark
                  ? AppColorTokens.bloomDarkTextSecondary
                  : AppColorTokens.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrap(bool isDark, List<Widget> body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Where it went',
                style: AppTheme.bloomDisplay(
                  16,
                  FontWeight.w600,
                  color: isDark
                      ? AppColorTokens.bloomDarkTextPrimary
                      : AppColorTokens.ink,
                ),
              ),
            ),
            Semantics(
              container: true,
              label: 'View all categories',
              button: true,
              onTap: onViewAll,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onViewAll,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          'All →',
                          style: AppTheme.bloomDisplay(
                            13,
                            FontWeight.w600,
                            color: AppColorTokens.violetPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...body,
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final amount = Text(
                    formatInr(slice.total),
                    style: AppTheme.bloomMono(
                      13,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextSecondary
                          : AppColorTokens.inkSecondary,
                    ),
                  );
                  final name = Text(
                    slice.name,
                    maxLines: constraints.maxWidth < 300 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bloomDisplay(
                      13,
                      FontWeight.w500,
                      color: isDark
                          ? AppColorTokens.bloomDarkTextPrimary
                          : AppColorTokens.ink,
                    ),
                  );

                  if (constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        name,
                        Align(
                          alignment: Alignment.centerRight,
                          child: amount,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: amount,
                        ),
                      ),
                    ],
                  );
                },
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
    final claim = const ClaimValidator().parse(insight);
    final names = ref.watch(claimDisplayNamesProvider).valueOrNull;
    final display = claim == null || names == null
        ? null
        : const ClaimRenderer().render(
            claim,
            categoryNames: names.categories,
            merchantNames: names.merchants,
          );
    if (claim == null || display == null) return const SizedBox.shrink();

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
                  display.title,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFF3DFB4)
                        : const Color(0xFF3D2E06),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  display.body,
                  style: AppTheme.bloomDisplay(
                    12,
                    FontWeight.w400,
                    color: isDark
                        ? AppColorTokens.bloomDarkTextSecondary
                        : const Color(0xFF7E6A45),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionsScreen(
                          initialTransactionIds: claim.evidenceIds.toSet(),
                          initialEvidenceTotalCount: claim.evidenceCount,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.help_outline_rounded, size: 17),
                    label: const Text('Why?'),
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

    return Semantics(
      button: true,
      onTap: onTap,
      child: MergeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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
                    currencyCode: txn.currencyCode,
                    currencySymbol: txn.currencySymbol,
                    size: 15,
                    weight: FontWeight.w500,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    return formatTxnClockTime(date);
  }
}
