import 'package:flutter/material.dart';

/// Geometry reserved by the floating navigation pill in [HomeShell].
const double kBottomNavHeight = 64;
const double kBottomNavBottomGap = 20;

/// Shared contract for content rendered underneath the floating navigation.
///
/// [HomeShell] adds the pill's height and gap to the tab Navigator's bottom
/// media padding. Scrollables can then use [contentPadding] even when their
/// own padding is explicit, and SafeAreas inherit the clearance. Scaffold FABs
/// use [floatingActionButtonLocation] because their default location ignores
/// overridden bottom padding.
abstract final class BloomBottomInset {
  static const FloatingActionButtonLocation floatingActionButtonLocation =
      _BloomNavAwareFabLocation();

  static double contentPadding(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  static MediaQueryData forTabContent(MediaQueryData mediaQuery) {
    final left = mediaQuery.padding.left > mediaQuery.viewPadding.left
        ? mediaQuery.padding.left
        : mediaQuery.viewPadding.left;
    final right = mediaQuery.padding.right > mediaQuery.viewPadding.right
        ? mediaQuery.padding.right
        : mediaQuery.viewPadding.right;
    final bottom = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.padding.bottom
        : mediaQuery.viewPadding.bottom +
            kBottomNavHeight +
            kBottomNavBottomGap;
    return mediaQuery.copyWith(
      padding: mediaQuery.padding.copyWith(
        left: left,
        right: right,
        bottom: bottom,
      ),
    );
  }
}

class _BloomNavAwareFabLocation extends FloatingActionButtonLocation {
  const _BloomNavAwareFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final defaultOffset =
        FloatingActionButtonLocation.endFloat.getOffset(geometry);
    final keyboardIsVisible =
        geometry.minInsets.bottom > geometry.minViewPadding.bottom;
    if (keyboardIsVisible) return defaultOffset;

    return defaultOffset.translate(
      0,
      -(kBottomNavHeight + kBottomNavBottomGap),
    );
  }
}
