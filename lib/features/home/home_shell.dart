import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bloom/bloom.dart';
import '../assistant/assistant_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../insights/insights_screen.dart';
import '../review/weekly_review_screen.dart';
import '../transactions/transactions_screen.dart';

import '../dashboard/dashboard_providers.dart';

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
/// - Independent Navigator stack per tab; back pops active tab stack before exiting.
/// - Integrated 10-second undo toast host.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  static const List<GlobalObjectKey<NavigatorState>> _navKeys = [
    GlobalObjectKey<NavigatorState>('home_tab_nav'),
    GlobalObjectKey<NavigatorState>('activity_tab_nav'),
    GlobalObjectKey<NavigatorState>('sort_tab_nav'),
    GlobalObjectKey<NavigatorState>('trends_tab_nav'),
  ];

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
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // Pop to root of current tab if tapped again
      _navKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: AppDurations.standard,
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _openAskPaisaTrack() {
    showBloomModalSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: AssistantScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<int>(homeTabControllerProvider, (previous, next) {
      if (next != _currentIndex && next >= 0 && next < _tabs.length) {
        _onTabTapped(next);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final currentNav = _navKeys[_currentIndex].currentState;
        if (currentNav != null && currentNav.canPop()) {
          currentNav.pop();
        } else if (_currentIndex != 0) {
          _onTabTapped(0);
        } else {
          // If at root of Home tab, allow system back / pop
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: BloomUndoToastHost(
          bottomOffset: 110,
          child: Stack(
            children: [
              // Swipeable PageView with independent tab navigators
              PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _tabs.length,
                itemBuilder: (context, index) {
                  return Navigator(
                    key: _navKeys[index],
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        builder: (_) => _tabs[index].screen,
                        settings: settings,
                      );
                    },
                  );
                },
              ),

              // Floating Nav Pill
              Positioned(
                left: 20,
                right: 20,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: _FloatingNavPill(
                  currentIndex: _currentIndex,
                  tabs: _tabs,
                  onTabSelected: _onTabTapped,
                  onAskTapped: _openAskPaisaTrack,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _FloatingNavPill extends StatelessWidget {
  const _FloatingNavPill({
    required this.currentIndex,
    required this.tabs,
    required this.onTabSelected,
    required this.onAskTapped,
    required this.isDark,
  });

  final int currentIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onAskTapped;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? AppColorTokens.bloomDarkCard : AppColorTokens.ink;
    final border = isDark
        ? Border.all(color: AppColorTokens.bloomDarkOutline, width: 1)
        : null;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.bloomNavPill),
        border: border,
        boxShadow: AppColorTokens.bloomNavPillShadow,
      ),
      child: Row(
        children: [
          // Four tabs left-aligned with equal spacing
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _NavTabItemButton(
                    item: tabs[i],
                    isSelected: currentIndex == i,
                    onTap: () => onTabSelected(i),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Ask Orb on the right
          _AskOrbButton(onTap: onAskTapped),
        ],
      ),
    );
  }
}

class _NavTabItemButton extends StatelessWidget {
  const _NavTabItemButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _TabItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Colors.white;
    const inactiveColor = AppColorTokens.inkQuaternary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? item.selectedIcon : item.icon,
              size: 19,
              color: isSelected ? activeColor : inactiveColor,
            ),
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

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 48,
        height: 48,
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
    );
  }
}
