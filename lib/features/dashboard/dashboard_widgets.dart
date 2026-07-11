import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/paisa_colors.dart';
import 'dashboard_providers.dart';

/// Section heading shared across dashboard cards. Quiet, uppercase-free label
/// (design-system.md §3): supports numbers without competing with them.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A labelled money amount card. [compact] tightens padding and type for the
/// two-up summary row; the full form keeps the leading icon disc.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.compact = false,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatInr(amount),
                style: theme.textTheme.titleMedium?.copyWith(
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

/// Colored pill showing net cash flow for the month header.
class NetFlowChip extends StatelessWidget {
  const NetFlowChip({super.key, required this.net});

  final double net;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isPositive = net >= 0;
    final color = isPositive ? paisa.credit : paisa.debit;
    final prefix = isPositive ? '+' : '−';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'Net $prefix${formatInr(net.abs())}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: AppTheme.tabularFigures,
        ),
      ),
    );
  }
}

/// Compact label-over-value tile for the net/pace strip. Optional [accent]
/// tints the value; [trailing] holds a small trend indicator.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent ?? theme.colorScheme.onSurface,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ranked horizontal bars of this month's top spending categories.
class CategoryBreakdownCard extends StatelessWidget {
  const CategoryBreakdownCard({
    super.key,
    required this.slices,
    this.onSliceTap,
  });

  final List<CategorySlice> slices;

  /// Invoked when a real category row is tapped (the aggregate "Other" slice,
  /// which has no single id, is not tappable).
  final void Function(CategorySlice slice)? onSliceTap;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Spending by category'),
            for (var i = 0; i < slices.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _CategoryRow(
                slice: slices[i],
                onTap: slices[i].categoryId == null || onSliceTap == null
                    ? null
                    : () => onSliceTap!(slices[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.slice, this.onTap});

  final CategorySlice slice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = CategoryVisuals.color(slice.categoryId);
    final icon = CategoryVisuals.icon(slice.icon);
    final pct = (slice.share * 100).round();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            // Name keeps priority (higher flex) and yields to the amount only
            // when the amount is genuinely wide; both ellipsize as a safety net.
            Expanded(
              flex: 3,
              child: Text(
                slice.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              flex: 2,
              child: Text(
                formatInr(slice.total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 36,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: slice.share.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: content,
      ),
    );
  }
}

/// Ranked list of this month's biggest merchants by spend.
class TopMerchantsCard extends StatelessWidget {
  const TopMerchantsCard({
    super.key,
    required this.merchants,
    this.onMerchantTap,
  });

  final List<MerchantStat> merchants;
  final void Function(MerchantStat merchant)? onMerchantTap;

  @override
  Widget build(BuildContext context) {
    if (merchants.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Top merchants'),
            for (var i = 0; i < merchants.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _MerchantRow(
                merchant: merchants[i],
                onTap: onMerchantTap == null
                    ? null
                    : () => onMerchantTap!(merchants[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MerchantRow extends StatelessWidget {
  const _MerchantRow({required this.merchant, this.onTap});

  final MerchantStat merchant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                merchant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                merchant.count == 1 ? '1 payment' : '${merchant.count} payments',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          formatInr(merchant.total),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: AppTheme.tabularFigures,
          ),
        ),
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: row,
      ),
    );
  }
}

/// Minimal single-line sparkline of six-month spend, no axes. Uses the info
/// accent so it reads as informational, not alarming.
class TrendSparkline extends StatelessWidget {
  const TrendSparkline({super.key, required this.points});

  final List<MonthPoint> points;

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _trendSemanticLabel() {
    final first = points.first.spend;
    final last = points.last.spend;
    final direction = last > first
        ? 'up'
        : last < first
            ? 'down'
            : 'flat';
    return 'Six-month spend trend, $direction. Latest month '
        '${formatInr(last)}.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final hasData = points.any((p) => p.spend > 0);
    if (points.length < 2 || !hasData) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('6-month spend trend'),
            SizedBox(
              height: 56,
              child: Semantics(
                label: _trendSemanticLabel(),
                child: CustomPaint(
                  painter: _SparklinePainter(
                    points: points,
                    lineColor: paisa.info,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _monthLabels[points.first.month.month - 1],
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  _monthLabels[points.last.month.month - 1],
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.lineColor});

  final List<MonthPoint> points;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final maxSpend = points.fold<double>(0, (m, p) => p.spend > m ? p.spend : m);
    final range = maxSpend <= 0 ? 1.0 : maxSpend;
    final dx = size.width / (points.length - 1);

    double yFor(double spend) {
      // Leave a small top/bottom margin so the peak/trough aren't clipped.
      const margin = 6.0;
      final usable = size.height - margin * 2;
      return margin + usable * (1 - spend / range);
    }

    final path = Path();
    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final o = Offset(dx * i, yFor(points[i].spend));
      offsets.add(o);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }

    // Soft fill under the line.
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = lineColor.withValues(alpha: 0.12),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );

    // Emphasise the latest month with a dot.
    canvas.drawCircle(
      offsets.last,
      3,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}
