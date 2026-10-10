import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transactions/detail/upi_qr_action.dart';

/// One Sort list-mode tile: avatar, payee, date/category line, signed amount,
/// then a footer of quick sort actions and the optional UPI QR button.
///
/// The whole tile is clipped to its rounded shape, so nothing (including the
/// 48dp QR target) can paint outside it. Tapping the body calls [onOpen].
class ReviewListRow extends StatelessWidget {
  const ReviewListRow({
    super.key,
    required this.item,
    required this.isDark,
    required this.onOpen,
    required this.onConfirm,
    required this.onRecategorize,
    required this.onSkip,
    required this.keepEnabled,
  });

  final TransactionReviewItem item;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onConfirm;
  final VoidCallback onRecategorize;
  final VoidCallback onSkip;
  final bool keepEnabled;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.bloomRow);
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.bloomCard;
    final isDebit = item.direction == TransactionDirection.debit;
    final signedAmount = isDebit ? -item.amount : item.amount;
    final spokenAmount = formatSourceAmount(
      signedAmount,
      currencyCode: item.currencyCode,
      currencySymbol: item.currencySymbol,
    );
    final direction = isDebit ? 'Expense' : 'Income';
    final lowTrustNote =
        item.isLowTrustParse ? ', Low confidence parse — verify details' : '';
    final statusLabel =
        item.status == 'needs_review' ? 'Needs review' : item.status;
    final rowActions = <CustomSemanticsAction, VoidCallback>{
      if (keepEnabled) const CustomSemanticsAction(label: 'Keep'): onConfirm,
      const CustomSemanticsAction(label: 'Change category'): onRecategorize,
      const CustomSemanticsAction(label: 'Skip'): onSkip,
    };
    final primary =
        isDark ? AppColorTokens.bloomDarkTextPrimary : AppColorTokens.ink;
    final tertiary = isDark
        ? AppColorTokens.bloomDarkTextTertiary
        : AppColorTokens.inkTertiary;
    final secondary = isDark
        ? AppColorTokens.bloomDarkTextSecondary
        : AppColorTokens.inkSecondary;
    final divider = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColorTokens.bloomHairline;

    final secondaryLine = [
      item.categoryName ?? 'Uncategorised',
      formatTxnTime(item.ts),
    ].join(' · ');

    final avatar = BloomCategoryTile(
      categoryId: item.categoryId,
      iconName: item.categoryIcon,
      size: 40,
      borderRadius: 14,
    );
    final amount = BloomAmount(
      amount: signedAmount,
      currencyCode: item.currencyCode,
      currencySymbol: item.currencySymbol,
      size: 15,
      weight: FontWeight.w600,
      maxLines: 2,
      textAlign: TextAlign.end,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.displayName,
          style: AppTheme.bloomDisplay(14, FontWeight.w600, color: primary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          secondaryLine,
          style: AppTheme.bloomDisplay(12, FontWeight.w400, color: secondary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                statusLabel,
                style:
                    AppTheme.bloomDisplay(11, FontWeight.w400, color: tertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.isLowTrustParse) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.warning_amber_rounded,
                size: 12,
                color: AppColorTokens.bloomGold,
              ),
            ],
          ],
        ),
      ],
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 24;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: amount),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(child: details),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
              child: amount,
            ),
          ],
        );
      },
    );

    ButtonStyle actionStyle(Color color) => TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: AppTheme.bloomDisplay(12, FontWeight.w600),
        );

    // Labelled buttons need ~280dp; below that (or at large text) switch to
    // 48dp icon buttons so the footer stays a single non-overflowing row.
    final iconOnly = MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    Widget action({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback? onPressed,
    }) {
      if (iconOnly) {
        return IconButton(
          tooltip: label,
          onPressed: onPressed,
          color: color,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Icon(icon, size: 20),
        );
      }
      return TextButton.icon(
        onPressed: onPressed,
        style: actionStyle(color),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    final actions = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        action(
          icon: Icons.check_rounded,
          label: 'Keep',
          color: AppColorTokens.bloomEmerald,
          onPressed: keepEnabled ? onConfirm : null,
        ),
        action(
          icon: Icons.sell_outlined,
          label: 'Category',
          color: secondary,
          onPressed: onRecategorize,
        ),
        action(
          icon: Icons.arrow_forward_rounded,
          label: 'Skip',
          color: secondary,
          onPressed: onSkip,
        ),
      ],
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${item.displayName}, ${item.categoryName ?? 'Uncategorised'}, '
          '$direction, $spokenAmount, ${formatActivityDateGroup(item.ts)}, '
          '$statusLabel$lowTrustNote',
      hint: keepEnabled
          ? 'Actions: Keep, Change category, Skip'
          : 'Actions: Change category, Skip. Keep is unavailable until a '
              'category guess or correction is ready.',
      customSemanticsActions: rowActions,
      child: Dismissible(
        key: ValueKey('review_${item.id}'),
        background: _swipeBackground(
          Alignment.centerLeft,
          AppColorTokens.bloomEmerald,
          Icons.check,
          radius,
        ),
        secondaryBackground: _swipeBackground(
          Alignment.centerRight,
          AppColorTokens.bloomGold,
          Icons.sell_outlined,
          radius,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onConfirm();
          } else {
            onRecategorize();
          }
          return false;
        },
        child: Material(
          key: ValueKey('review_tile_${item.id}'),
          color: bg,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: 'Open transaction details',
                onTap: onOpen,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: body,
                    ),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 10, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: actions),
                    UpiQrAction(
                      counterpartyVpa: item.counterpartyVpa,
                      transactionTitle: item.displayName,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground(
    Alignment alignment,
    Color color,
    IconData icon,
    BorderRadius radius,
  ) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: radius),
      child: Icon(icon, color: Colors.white),
    );
  }
}
