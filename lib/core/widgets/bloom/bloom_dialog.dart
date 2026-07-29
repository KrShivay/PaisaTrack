import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Shared Bloom-styled dialog helper, analogous to [showBloomModalSheet] for
/// bottom sheets. Wraps [showDialog] with consistent corner radius,
/// action-button styling, and scrim. All dialogs should use this instead of
/// calling [showDialog] directly.
///
/// The [builder] receives an [AlertDialog] (or custom widget). If you want the
/// standard Bloom chrome, use [showBloomAlertDialog] which builds the
/// [AlertDialog] for you.
Future<T?> showBloomDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: const Color(0xA61B1830), // ~65% scrim, matching Bloom sheets
    useRootNavigator: useRootNavigator,
    builder: (context) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.bloomCard),
            ),
            backgroundColor:
                theme.brightness == Brightness.dark
                    ? AppColorTokens.bloomDarkCard
                    : AppColorTokens.bloomBase,
          ),
        ),
        child: builder(context),
      );
    },
  );
}

/// Convenience wrapper that builds a Bloom-styled [AlertDialog] with
/// consistent title/content styling and Bloom-themed action buttons.
Future<T?> showBloomAlertDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  required List<Widget> actions,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showBloomDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: content,
      actions: actions,
    ),
  );
}
