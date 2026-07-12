import 'package:flutter/material.dart';

import '../../data/models/normalized_transaction_record.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../theme/category_visuals.dart';
import '../theme/paisa_colors.dart';

class TransactionAmount extends StatelessWidget {
  const TransactionAmount({
    super.key,
    required this.amount,
    required this.direction,
    this.isSpending = true,
    this.style,
  });

  final double amount;
  final TransactionDirection direction;
  final bool isSpending;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paisa = PaisaColors.of(context);
    final isCredit = direction == TransactionDirection.credit;
    final color = isCredit
        ? paisa.credit
        : isSpending
            ? paisa.debit
            : theme.colorScheme.onSurface;
    final sign = isCredit ? '+' : '-';

    return Text(
      '$sign${formatInr(amount)}',
      maxLines: 1,
      softWrap: false,
      style: (style ?? theme.textTheme.titleMedium)?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontFeatures: AppTheme.tabularFigures,
      ),
    );
  }
}

class TransactionCategoryIcon extends StatelessWidget {
  const TransactionCategoryIcon({
    super.key,
    required this.categoryId,
    required this.categoryIcon,
    required this.categoryLabel,
    this.selected = false,
  });

  final String? categoryId;
  final String? categoryIcon;
  final String categoryLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = CategoryVisuals.color(categoryId);
    final icon = selected ? Icons.check : CategoryVisuals.icon(categoryIcon);
    final iconColor = selected ? theme.colorScheme.onPrimary : color;
    final backgroundColor =
        selected ? theme.colorScheme.primary : color.withValues(alpha: 0.15);

    return Semantics(
      label: selected ? 'Selected, $categoryLabel' : categoryLabel,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.merchantName,
    required this.amount,
    required this.direction,
    required this.categoryLabel,
    required this.timeLabel,
    this.categoryId,
    this.categoryIcon,
    this.accountLabel,
    this.statusLabel,
    this.categoryIsSpending = true,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final String merchantName;
  final double amount;
  final TransactionDirection direction;
  final String categoryLabel;
  final String timeLabel;
  final String? categoryId;
  final String? categoryIcon;
  final String? accountLabel;
  final String? statusLabel;
  final bool categoryIsSpending;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = [
      categoryLabel,
      if (timeLabel.isNotEmpty) timeLabel,
    ];
    final tertiaryParts = [
      if (accountLabel != null && accountLabel!.trim().isNotEmpty)
        accountLabel!.trim(),
      if (statusLabel != null && statusLabel!.trim().isNotEmpty)
        statusLabel!.trim(),
    ];
    final status = statusLabel?.trim();

    return Semantics(
      button: onTap != null,
      label:
          '$merchantName, $categoryLabel, ${direction == TransactionDirection.credit ? 'plus' : 'minus'} ${formatInr(amount)}, $timeLabel${status == null || status.isEmpty ? '' : ', $status'}.',
      child: ListTile(
        minVerticalPadding: AppSpacing.sm,
        selected: selected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: TransactionCategoryIcon(
          selected: selected,
          categoryId: categoryId,
          categoryIcon: categoryIcon,
          categoryLabel: categoryLabel,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                merchantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TransactionAmount(
              amount: amount,
              direction: direction,
              isSpending: categoryIsSpending,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitleParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (tertiaryParts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  tertiaryParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
