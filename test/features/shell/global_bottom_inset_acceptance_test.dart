import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/home/home_shell.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

const _navigationKey = ValueKey('floating_navigation_pill');
const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);

const _destinations = <HomeNavigationDestination>[
  HomeNavigationDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  HomeNavigationDestination(
    label: 'Activity',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  HomeNavigationDestination(
    label: 'Sort',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check_rounded,
  ),
  HomeNavigationDestination(
    label: 'Trends',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
];

class _RouteShell extends StatefulWidget {
  const _RouteShell({required this.initialScreen, this.initialTab = 0});

  final Widget initialScreen;
  final int initialTab;

  @override
  State<_RouteShell> createState() => _RouteShellState();
}

class _RouteShellState extends State<_RouteShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late int _currentTab = widget.initialTab;

  Widget _screenForTab(int index) => switch (index) {
        0 => const Scaffold(body: Center(child: Text('Synthetic Home route'))),
        1 => const TransactionsScreen(),
        2 => const WeeklyReviewScreen(),
        _ => const InsightsScreen(),
      };

  void _selectTab(int index) {
    setState(() => _currentTab = index);
    _navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => _screenForTab(index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceMediaQuery = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: BloomBottomInset.forTabContent(deviceMediaQuery),
          child: Navigator(
            key: _navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => widget.initialScreen,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: deviceMediaQuery.padding.bottom + kBottomNavBottomGap,
          child: Material(
            type: MaterialType.transparency,
            child: HomeFloatingNavPill(
              key: _navigationKey,
              currentIndex: _currentTab,
              destinations: _destinations,
              onTabSelected: _selectTab,
              onAskTapped: () {},
              isDark: true,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pumpRoutes(
  WidgetTester tester, {
  required Widget initialScreen,
  int initialTab = 0,
  Size size = const Size(402, 874),
  double systemBottomInset = 24,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: systemBottomInset);
  tester.view.viewInsets = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardAggregateProvider.overrideWith(
          (ref) async => _emptyDashboardAggregate,
        ),
        activeInsightsProvider.overrideWith(
          (ref) => Stream<List<Insight>>.value(const []),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
            ),
          );
        },
        home: _RouteShell(
          initialScreen: initialScreen,
          initialTab: initialTab,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void _expectAboveNavigation(WidgetTester tester, Finder target) {
  final targetRect = tester.getRect(target);
  final navigationRect = tester.getRect(find.byType(HomeFloatingNavPill));
  expect(targetRect.bottom, lessThanOrEqualTo(navigationRect.top));
}

Future<void> _scrollToEnd(WidgetTester tester, Type screenType) async {
  final scrollable = find
      .descendant(
        of: find.byType(screenType),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final inset in [24.0, 48.0]) {
    final navigationMode = inset == 24 ? 'gesture' : 'three-button';
    testWidgets(
      'Trends final section clears the real $navigationMode navigation pill',
      (tester) async {
        await _pumpRoutes(
          tester,
          initialScreen: const InsightsScreen(),
          initialTab: 3,
          systemBottomInset: inset,
        );

        final finalSection = find.text('No merchant data for this period');
        await _scrollToEnd(tester, InsightsScreen);
        expect(finalSection, findsOneWidget);
        _expectAboveNavigation(tester, finalSection);
        expect(tester.getSize(find.byType(HomeFloatingNavPill)).height, 64);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact landscape Trends final section clears navigation at 1.5x text',
    (tester) async {
      await _pumpRoutes(
        tester,
        initialScreen: const InsightsScreen(),
        initialTab: 3,
        size: const Size(568, 320),
        systemBottomInset: 24,
        textScale: 1.5,
      );
      final finalSection = find.text('No merchant data for this period');
      await _scrollToEnd(tester, InsightsScreen);
      expect(finalSection, findsOneWidget);
      _expectAboveNavigation(tester, finalSection);
      expect(tester.takeException(), isNull);
    },
  );
}
