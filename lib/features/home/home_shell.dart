import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../../data/repositories/trends_inbox_repository.dart';
import '../assistant/assistant_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../insights/insights_screen.dart';
import '../review/weekly_review_screen.dart';
import '../transactions/transactions_screen.dart';

import '../dashboard/dashboard_providers.dart';

const Duration _homeExitConfirmationWindow = Duration(seconds: 2);

/// Post-onboarding Bloom app shell with 4 fixed destinations and floating nav pill.
///
/// Destinations:
/// 1. Home (`DashboardScreen`)
/// 2. Activity (`TransactionsScreen`)
/// 3. Sort (`WeeklyReviewScreen`)
/// 4. Trends (`InsightsScreen`)
///
/// Features:
/// - Floating 64px nav pill inset 20px, 30px above bottom safe area.
/// - 48px Ask orb triggering Ask PaisaTrack root sheet.
/// - PageView swipe navigation with 250ms transition.
/// - Independent, retained Navigator stack per tab with one shell back contract.
/// - The root app overlay hosts the shared 10-second undo toast.

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;
  bool _trendsLeaveScheduled = false;
  bool _handlingBack = false;
  int _navigationRevision = 0;
  bool _exitConfirmationArmed = false;
  bool _rootRouteCurrent = true;
  bool _hasObservedKeyboardVisibility = false;
  bool _keyboardVisible = false;
  Timer? _exitConfirmationTimer;
  final GlobalKey<ScaffoldMessengerState> _shellMessengerKey =
      GlobalKey<ScaffoldMessengerState>(debugLabel: 'home shell messenger');

  static const int _trendsTabIndex = 3;

  late final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    _tabs.length,
    (index) => GlobalKey<NavigatorState>(
      debugLabel: '${_tabs[index].label.toLowerCase()} tab navigator',
    ),
    growable: false,
  );
  late final List<_ShellTabRouteObserver> _tabRouteObservers = List.generate(
    _tabs.length,
    (_) => _ShellTabRouteObserver(onTopChanged: _invalidateExitConfirmation),
    growable: false,
  );

  static const List<_TabItem> _tabs = [
    _TabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      screen: DashboardScreen(),
    ),
    _TabItem(
      label: 'Activity',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      screen: TransactionsScreen(),
    ),
    _TabItem(
      label: 'Sort',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check_rounded,
      screen: WeeklyReviewScreen(),
    ),
    _TabItem(
      label: 'Trends',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      screen: InsightsScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _clearExitConfirmation();
    _markTrendsSeen();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidateExitConfirmation();
    if (switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        true,
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
    }) {
      _markTrendsSeen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeIsCurrent = ModalRoute.isCurrentOf(context);
    if (routeIsCurrent != null && routeIsCurrent != _rootRouteCurrent) {
      _rootRouteCurrent = routeIsCurrent;
      _invalidateExitConfirmation();
    }

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (_hasObservedKeyboardVisibility && keyboardVisible != _keyboardVisible) {
      _invalidateExitConfirmation();
    }
    _keyboardVisible = keyboardVisible;
    _hasObservedKeyboardVisibility = true;
  }

  void _clearExitConfirmation() {
    _exitConfirmationTimer?.cancel();
    _exitConfirmationTimer = null;
    final wasArmed = _exitConfirmationArmed;
    _exitConfirmationArmed = false;
    if (wasArmed) _shellMessengerKey.currentState?.hideCurrentSnackBar();
  }

  void _invalidateExitConfirmation() {
    _navigationRevision++;
    _clearExitConfirmation();
  }

  void _armExitConfirmation() {
    _exitConfirmationArmed = true;
    // The exit prompt must start immediately; an existing informational
    // snackbar cannot be allowed to delay it past the two-second window.
    _shellMessengerKey.currentState?.clearSnackBars();
    const bottomClearance = kBottomNavHeight + kBottomNavBottomGap + 8;
    _shellMessengerKey.currentState?.showSnackBar(
      SnackBar(
        key: const ValueKey('home-exit-snackbar'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, bottomClearance),
        content: Semantics(
          liveRegion: true,
          child: const Text('Press back again to exit'),
        ),
        duration: _homeExitConfirmationWindow,
      ),
    );
    _exitConfirmationTimer = Timer(_homeExitConfirmationWindow, () {
      _exitConfirmationTimer = null;
      _exitConfirmationArmed = false;
    });
  }

  Future<void> _handleSystemBack() async {
    if (_handlingBack || !mounted) return;
    _handlingBack = true;
    try {
      final requestRevision = _navigationRevision;
      final requestTab = _currentIndex;
      final currentNavigator = _navKeys[requestTab].currentState;
      final wasHandled =
          currentNavigator != null && await currentNavigator.maybePop();
      if (!mounted ||
          requestRevision != _navigationRevision ||
          requestTab != _currentIndex ||
          !_rootRouteCurrent) {
        return;
      }
      if (wasHandled) {
        _clearExitConfirmation();
        return;
      }

      if (_currentIndex != 0) {
        _clearExitConfirmation();
        _onTabTapped(0);
        return;
      }

      // Never pop the parent route: onboarding and permission recovery are
      // owned by app startup, not by the Home exit affordance.
      if (!_rootRouteCurrent) {
        _clearExitConfirmation();
        return;
      }

      if (_exitConfirmationArmed) {
        _clearExitConfirmation();
        await SystemNavigator.pop();
      } else {
        _armExitConfirmation();
      }
    } finally {
      _handlingBack = false;
    }
  }

  void _markTrendsSeen() {
    if (_currentIndex != _trendsTabIndex || _trendsLeaveScheduled) return;
    final items = ref.read(trendsInboxItemsProvider).valueOrNull ?? const [];
    final keys = items
        .where(
          (item) => item.isCurrent && item.state == TrendsInboxState.newItem,
        )
        .map((item) => item.key)
        .toList(growable: false);
    if (keys.isEmpty) return;
    _trendsLeaveScheduled = true;
    final markSeen = ref.read(markTrendsInboxSeenProvider);
    unawaited(() async {
      try {
        await markSeen(keys);
        if (mounted) ref.invalidate(trendsInboxItemsProvider);
      } on Object {
        _trendsLeaveScheduled = false;
      }
    }());
  }

  void _onTabTapped(int index) {
    _invalidateExitConfirmation();
    if (index == _currentIndex) {
      _syncTabSelection();
      // Pop to root of current tab if tapped again
      _navKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    if (_currentIndex == _trendsTabIndex) _markTrendsSeen();
    if (index == _trendsTabIndex) _trendsLeaveScheduled = false;
    setState(() {
      _currentIndex = index;
    });
    _syncTabSelection();
    _pageController.animateToPage(
      index,
      duration: AppDurations.standard,
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      _invalidateExitConfirmation();
      if (_currentIndex == _trendsTabIndex) _markTrendsSeen();
      if (index == _trendsTabIndex) _trendsLeaveScheduled = false;
      setState(() {
        _currentIndex = index;
      });
      _syncTabSelection();
    }
  }

  void _syncTabSelection() {
    if (ref.read(homeTabControllerProvider) != _currentIndex) {
      ref.read(homeTabControllerProvider.notifier).state = _currentIndex;
    }
  }

  void _openAskPaisaTrack() {
    showBloomFullScreenSheet(
      context: context,
      showBack: false,
      showClose: false,
      backgroundColor: AppColorTokens.bloomDarkBase,
      headerBuilder: AssistantScreen.sheetHeader,
      avoidKeyboard: true,
      builder: (_) => const AssistantScreen(showSheetHeader: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final leftInset = mediaQuery.padding.left > mediaQuery.viewPadding.left
        ? mediaQuery.padding.left
        : mediaQuery.viewPadding.left;
    final rightInset = mediaQuery.padding.right > mediaQuery.viewPadding.right
        ? mediaQuery.padding.right
        : mediaQuery.viewPadding.right;
    final inboxItems = ref.watch(trendsInboxEnabledProvider)
        ? ref.watch(trendsInboxItemsProvider).valueOrNull ?? const []
        : const [];
    final newTrendsCount = inboxItems
        .where(
          (item) => item.isCurrent && item.state == TrendsInboxState.newItem,
        )
        .length;

    ref.listen<int>(homeTabControllerProvider, (previous, next) {
      if (next != _currentIndex && next >= 0 && next < _tabs.length) {
        _onTabTapped(next);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: ScaffoldMessenger(
        key: _shellMessengerKey,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Swipeable PageView with independent tab navigators
              MediaQuery(
                data: BloomBottomInset.forTabContent(MediaQuery.of(context)),
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _tabs.length,
                  itemBuilder: (context, index) {
                    final theme = Theme.of(context);
                    final androidTransitions = theme
                        .pageTransitionsTheme.builders[TargetPlatform.android];
                    final suspendPredictiveBack = (index != _currentIndex ||
                            !_rootRouteCurrent) &&
                        (androidTransitions
                                is PredictiveBackPageTransitionsBuilder ||
                            androidTransitions
                                is PredictiveBackFullscreenPageTransitionsBuilder);
                    final tabNavigator = Navigator(
                      key: _navKeys[index],
                      observers: [_tabRouteObservers[index]],
                      onGenerateRoute: (settings) {
                        return MaterialPageRoute<void>(
                          builder: (_) => _tabs[index].screen,
                          settings: settings,
                        );
                      },
                    );
                    final navigator = suspendPredictiveBack
                        ? Theme(
                            data: theme.copyWith(
                              pageTransitionsTheme: PageTransitionsTheme(
                                builders: {
                                  ...theme.pageTransitionsTheme.builders,
                                  TargetPlatform.android:
                                      const FadeForwardsPageTransitionsBuilder(),
                                },
                              ),
                            ),
                            child: tabNavigator,
                          )
                        : tabNavigator;
                    return _KeepAliveTab(
                      key: ValueKey<String>('home_tab_page_$index'),
                      child: TickerMode(
                        enabled: index == _currentIndex && _rootRouteCurrent,
                        child: navigator,
                      ),
                    );
                  },
                ),
              ),

              // Floating Nav Pill
              Positioned(
                left: leftInset + 20,
                right: rightInset + 20,
                bottom:
                    MediaQuery.paddingOf(context).bottom + kBottomNavBottomGap,
                child: HomeFloatingNavPill(
                  currentIndex: _currentIndex,
                  destinations: _tabs,
                  onTabSelected: _onTabTapped,
                  onAskTapped: _openAskPaisaTrack,
                  isDark: isDark,
                  trendsNewCount: newTrendsCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ShellTabRouteObserver extends NavigatorObserver {
  _ShellTabRouteObserver({required this.onTopChanged});

  final void Function() onTopChanged;

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) {
    onTopChanged();
  }
}

class _TabItem extends HomeNavigationDestination {
  const _TabItem({
    required super.label,
    required super.icon,
    required super.selectedIcon,
    required this.screen,
  });

  final Widget screen;
}

/// A single destination rendered by the floating home navigation.
class HomeNavigationDestination {
  const HomeNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating navigation presentation, kept independent of the tab routes so it
/// can be tested without constructing the database-backed app shell.
class HomeFloatingNavPill extends StatelessWidget {
  const HomeFloatingNavPill({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.onTabSelected,
    required this.onAskTapped,
    required this.isDark,
    this.trendsNewCount = 0,
  });

  final int currentIndex;
  final List<HomeNavigationDestination> destinations;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onAskTapped;
  final bool isDark;
  final int trendsNewCount;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.ink;
    final border = isDark
        ? Border.all(color: AppColorTokens.bloomDarkOutline, width: 1)
        : null;

    return Container(
      key: const ValueKey('floating_navigation_pill'),
      height: kBottomNavHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.bloomNavPill),
        border: border,
        boxShadow: AppColorTokens.bloomNavPillShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth - 56) / destinations.length;
          final showLabels =
              tabWidth >= 68 && MediaQuery.textScalerOf(context).scale(1) < 1.5;
          return Row(
            children: [
              // Four tabs left-aligned with equal spacing
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      _NavTabItemButton(
                        item: destinations[i],
                        isSelected: currentIndex == i,
                        showLabel: showLabels,
                        newCount: destinations[i].label == 'Trends'
                            ? trendsNewCount
                            : 0,
                        onTap: () => onTabSelected(i),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Ask Orb on the right
              _AskOrbButton(onTap: onAskTapped),
            ],
          );
        },
      ),
    );
  }
}

class _NavTabItemButton extends StatelessWidget {
  const _NavTabItemButton({
    required this.item,
    required this.isSelected,
    required this.showLabel,
    required this.newCount,
    required this.onTap,
  });

  final HomeNavigationDestination item;
  final bool isSelected;
  final bool showLabel;
  final int newCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Colors.white;
    const inactiveColor = AppColorTokens.inkQuaternary;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          newCount == 0 ? item.label : '${item.label}, $newCount new insights',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: AppSizes.minTouchTarget,
          height: AppSizes.minTouchTarget,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: newCount == 0
                    ? Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        size: 19,
                        color: isSelected ? activeColor : inactiveColor,
                      )
                    : Badge.count(
                        count: newCount,
                        backgroundColor: AppColorTokens.violetPrimary,
                        textColor: Colors.white,
                        child: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          size: 19,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                      ),
              ),
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: AppTheme.bloomDisplay(
                    9,
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AskOrbButton extends StatefulWidget {
  const _AskOrbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AskOrbButton> createState() => _AskOrbButtonState();
}

class _AskOrbButtonState extends State<_AskOrbButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppDurations.bloomAskOrbPulse,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!useReduceMotion(context) && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (useReduceMotion(context) && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = useReduceMotion(context);

    return Semantics(
      button: true,
      label: 'Ask PaisaTrack',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: AppSizes.minTouchTarget,
          height: AppSizes.minTouchTarget,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing ring animation
              if (!reduceMotion)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final t = _pulseController.value;
                    final scale = 1.0 + (0.35 * t);
                    final opacity = (0.5 * (1 - t)).clamp(0.0, 1.0);

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColorTokens.bloomEmerald.withValues(
                              alpha: opacity,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              // Orb
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColorTokens.bloomEmeraldGradient,
                  boxShadow: AppColorTokens.bloomAskOrbGlow,
                ),
                child: const Center(
                  child: Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: AppColorTokens.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
