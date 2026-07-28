import 'package:flutter/material.dart';
import 'bloom_sheet_scaffold.dart';

/// Presents a full-screen, draggable Bloom sheet.
/// This fulfills T-152a requirements: full-height draggable route, 44x5 grab handle,
/// 30px corner radius, swipe-down dismissal, mandatory visible exit, and scrim fade 0 -> 0.65.
Future<T?> showBloomFullScreenSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool showBack = true,
  bool showClose = false,
  VoidCallback? onBack,
  VoidCallback? onClose,
}) {
  assert(
    showBack || showClose,
    'T-152a: No screen built on this route can be reached without an exit affordance.',
  );

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xA61B1830), // ~65% opacity #1B1830
    builder: (BuildContext context) {
      // By wrapping in a FractionallySizedBox with heightFactor: 1.0, we force full height.
      // The BloomSheetScaffold already provides the 44x5 handle and 30px corner radius.
      return FractionallySizedBox(
        heightFactor: 1.0, // Full height
        child: BloomSheetScaffold(
          title: title,
          showBack: showBack,
          showClose: showClose,
          onBack: onBack,
          onClose: onClose,
          child: builder(context),
        ),
      );
    },
  );
}
