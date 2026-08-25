import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/app_theme.dart';

/// Inline notice row for errors and warnings.
///
/// Matches the Bloom design: "Errors: inline gold/red rows with one sentence
/// and one action. Never a modal alert."
class BloomNotice extends StatelessWidget {
  const BloomNotice.warning({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.warning_amber_rounded,
  }) : _variant = _NoticeVariant.warning;

  const BloomNotice.error({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.error_outline_rounded,
  }) : _variant = _NoticeVariant.error;

  /// The single sentence of explanation.
  final String message;

  /// Optional action button label (e.g. "Open settings", "Retry").
  final String? actionLabel;

  /// Callback for the action button.
  final VoidCallback? onAction;

  /// Leading icon. Defaults to warning/error icon.
  final IconData icon;

  final _NoticeVariant _variant;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = _resolveColors(isDark);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.bloomRow),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.tileBg,
              borderRadius: BorderRadius.circular(AppRadius.bloomIconTile),
            ),
            child: Center(child: Icon(icon, size: 18, color: colors.iconColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w500,
                    color: colors.textColor,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onAction,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 4,
                        ),
                        child: Text(
                          actionLabel!,
                          style: AppTheme.bloomDisplay(
                            12,
                            FontWeight.w600,
                            color: colors.actionColor,
                          ),
                        ),
                      ),
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

  _NoticeColors _resolveColors(bool isDark) {
    return switch (_variant) {
      _NoticeVariant.warning => _NoticeColors(
        background: isDark
            ? AppColorTokens.bloomGold.withValues(alpha: 0.12)
            : AppColorTokens.bloomWarningBg,
        border: isDark
            ? AppColorTokens.bloomGold.withValues(alpha: 0.3)
            : AppColorTokens.bloomWarningBorder,
        tileBg: isDark
            ? AppColorTokens.bloomGold.withValues(alpha: 0.18)
            : const Color(0xFFF7E5BE),
        iconColor: isDark
            ? AppColorTokens.bloomGold
            : AppColorTokens.bloomWarningText,
        textColor: isDark
            ? AppColorTokens.bloomDarkTextPrimary
            : AppColorTokens.bloomWarningText,
        actionColor: isDark
            ? AppColorTokens.violetLight
            : AppColorTokens.violetPrimary,
      ),
      _NoticeVariant.error => _NoticeColors(
        background: isDark
            ? AppColorTokens.bloomDebitDark.withValues(alpha: 0.12)
            : const Color(0xFFFDF2F3),
        border: isDark
            ? AppColorTokens.bloomDebitDark.withValues(alpha: 0.3)
            : const Color(0xFFF4D2D4),
        tileBg: isDark
            ? AppColorTokens.bloomDebitDark.withValues(alpha: 0.18)
            : const Color(0xFFFDE8E8),
        iconColor: isDark
            ? AppColorTokens.bloomDebitDark
            : AppColorTokens.bloomDebitLight,
        textColor: isDark
            ? AppColorTokens.bloomDarkTextPrimary
            : AppColorTokens.bloomDebitLight,
        actionColor: isDark
            ? AppColorTokens.violetLight
            : AppColorTokens.violetPrimary,
      ),
    };
  }
}

enum _NoticeVariant { warning, error }

class _NoticeColors {
  const _NoticeColors({
    required this.background,
    required this.border,
    required this.tileBg,
    required this.iconColor,
    required this.textColor,
    required this.actionColor,
  });

  final Color background;
  final Color border;
  final Color tileBg;
  final Color iconColor;
  final Color textColor;
  final Color actionColor;
}
