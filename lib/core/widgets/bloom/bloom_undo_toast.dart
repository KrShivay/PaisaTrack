import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_tokens.dart';
import '../../theme/app_theme.dart';
import '../../undo/undo_controller.dart';
import 'bloom_bottom_inset.dart';

/// Tracks root routes so the toast can clear Home's navigation pill only when
/// Home is the visible route.
class BloomUndoToastRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];
  final ValueNotifier<bool> hasPushedRoute = ValueNotifier(false);
  final ValueNotifier<bool> hasBlockingPopupRoute = ValueNotifier(false);
  NavigatorState? _navigator;

  void _trackNavigator(Route<dynamic> route) {
    final navigator = route.navigator;
    if (navigator != null && navigator != _navigator) {
      _navigator = navigator;
      _routes.clear();
    }
  }

  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hasPushedRoute.value = _routes.length > 1;
      final topRoute = _routes.isEmpty ? null : _routes.last;
      hasBlockingPopupRoute.value =
          topRoute is PopupRoute && topRoute is! ModalBottomSheetRoute;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _trackNavigator(route);
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _trackNavigator(route);
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _trackNavigator(route);
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _trackNavigator(newRoute);
    final oldIndex = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldIndex >= 0) {
      if (newRoute == null) {
        _routes.removeAt(oldIndex);
      } else {
        _routes[oldIndex] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _update();
  }
}

/// Shared MaterialApp.builder implementation for production and widget tests.
Widget buildBloomUndoToastAppBuilder(
  BuildContext context,
  Widget? child, {
  required BloomUndoToastRouteObserver routeObserver,
  required bool homeNavigationVisible,
}) {
  return BloomUndoToastHost(
    routeObserver: routeObserver,
    homeNavigationVisible: homeNavigationVisible,
    child: child ?? const SizedBox.shrink(),
  );
}

/// Floating 10-second undo toast host for the root app overlay.
class BloomUndoToastHost extends ConsumerWidget {
  const BloomUndoToastHost({
    super.key,
    required this.child,
    this.routeObserver,
    this.homeNavigationVisible = false,
    this.bottomOffset,
  });

  final Widget child;
  final BloomUndoToastRouteObserver? routeObserver;
  final bool homeNavigationVisible;

  /// Optional fixed offset for isolated hosts; the app host computes its inset.
  final double? bottomOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(undoControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<bool>(
      valueListenable: routeObserver?.hasPushedRoute ?? _noPushedRoute,
      builder: (context, hasPushedRoute, _) {
        return ValueListenableBuilder<bool>(
          valueListenable:
              routeObserver?.hasBlockingPopupRoute ?? _noBlockingPopupRoute,
          builder: (context, hasBlockingPopupRoute, _) {
            final media = MediaQuery.of(context);
            final homePillVisible = homeNavigationVisible && !hasPushedRoute;
            final visibleToken = hasBlockingPopupRoute ? null : token;
            final computedBottomOffset = homePillVisible
                ? media.padding.bottom +
                    kBottomNavHeight +
                    kBottomNavBottomGap +
                    8
                : media.padding.bottom + media.viewInsets.bottom + 96;

            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                AnimatedPositioned(
                  duration: AppDurations.fast,
                  curve: Curves.easeOut,
                  left: 20,
                  right: 20,
                  bottom: visibleToken != null
                      ? bottomOffset ?? computedBottomOffset
                      : -70,
                  child: AnimatedOpacity(
                    duration: AppDurations.fast,
                    opacity: visibleToken != null ? 1.0 : 0.0,
                    child: visibleToken != null
                        ? _ToastContent(
                            token: visibleToken,
                            isDark: isDark,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static final ValueNotifier<bool> _noPushedRoute = ValueNotifier(false);
  static final ValueNotifier<bool> _noBlockingPopupRoute = ValueNotifier(false);
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
        key: const Key('bloom-undo-toast'),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.bloomRow),
          border: border,
          boxShadow: AppColorTokens.bloomNavPillShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
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
            ),
            const SizedBox(width: 12),
            TextButton(
              key: const Key('bloom-undo-button'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor:
                    AppColorTokens.bloomEmerald.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: () {
                ref.read(undoControllerProvider.notifier).undo();
              },
              child: Text(
                'Undo',
                style: AppTheme.bloomDisplay(
                  13,
                  FontWeight.w600,
                  color: AppColorTokens.bloomEmerald,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
