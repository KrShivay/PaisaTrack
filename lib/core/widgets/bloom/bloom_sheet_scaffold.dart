import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/app_theme.dart';

/// Standard Bloom draggable sheet container with top grab handle and back/close affordance.
class BloomSheetScaffold extends StatelessWidget {
  const BloomSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.showBack = true,
    this.showClose = false,
    this.onBack,
    this.onClose,
    this.backgroundColor,
    this.actions,
  });

  final Widget child;
  final String? title;

  /// Shows left `←` back chevron.
  final bool showBack;

  /// Shows right `✕` close button.
  final bool showClose;

  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final Color? backgroundColor;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? AppColorTokens.bloomDarkBase : AppColorTokens.bloomBase);
    final handleColor =
        isDark ? AppColorTokens.bloomDarkOutline : const Color(0xFFDED8F5);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.bloomSheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          // Grab handle (44x5)
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          if (title != null ||
              showBack ||
              showClose ||
              (actions != null && actions!.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: AppTheme.bloomDisplay(
                          18,
                          FontWeight.w700,
                          color: isDark
                              ? AppColorTokens.bloomDarkTextPrimary
                              : AppColorTokens.ink,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (actions != null) ...actions!,
                  if (showClose)
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed:
                          onClose ?? () => Navigator.of(context).maybePop(),
                    ),
                ],
              ),
            ),
          ],
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Helper function to present a Bloom sheet modal.
Future<T?> showBloomModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
  bool isDismissible = true,
  Color barrierColor = const Color(0xA61B1830), // ~65% scrim
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    barrierColor: barrierColor,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: builder(context),
      );
    },
  );
}
