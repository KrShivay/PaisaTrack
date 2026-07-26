import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_tokens.dart';
import '../../theme/app_theme.dart';
import '../../undo/undo_controller.dart';

/// Floating 10-second undo toast host anchored above the floating navigation pill.
class BloomUndoToastHost extends ConsumerWidget {
  const BloomUndoToastHost({
    super.key,
    required this.child,
    this.bottomOffset = 96,
  });

  final Widget child;

  /// Bottom offset in logical px to position the toast above floating chrome.
  final double bottomOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(undoControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        child,
        AnimatedPositioned(
          duration: AppDurations.fast,
          curve: Curves.easeOut,
          left: 20,
          right: 20,
          bottom: token != null ? bottomOffset : -70,
          child: AnimatedOpacity(
            duration: AppDurations.fast,
            opacity: token != null ? 1.0 : 0.0,
            child: token != null
                ? _ToastContent(
                    token: token,
                    isDark: isDark,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _ToastContent extends ConsumerWidget {
  const _ToastContent({
    required this.token,
    required this.isDark,
  });

  final UndoToken token;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.ink;
    final border =
        isDark ? Border.all(color: AppColorTokens.bloomDarkOutline) : null;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
          border: border,
          boxShadow: AppColorTokens.bloomNavPillShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                token.message,
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w500,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                ref.read(undoControllerProvider.notifier).undo();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColorTokens.bloomEmerald.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Undo',
                  style: AppTheme.bloomDisplay(
                    13,
                    FontWeight.w600,
                    color: AppColorTokens.bloomEmerald,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
