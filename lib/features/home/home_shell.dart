import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../insights/insights_screen.dart';
import '../review/weekly_review_screen.dart';
import '../transactions/transactions_screen.dart';

/// Post-onboarding app shell with stable primary destinations.
///
/// Secondary capabilities live inside those destinations or Settings. The tab
/// list deliberately does not depend on feature flags, so navigation does not
/// jump as optional local-model features are enabled.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _home = _Tab(
    screen: DashboardScreen(),
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  );
  static const _transactions = _Tab(
    screen: TransactionsScreen(),
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Transactions',
  );
  static const _review = _Tab(
    screen: WeeklyReviewScreen(),
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check,
    label: 'Review',
  );
  static const _insights = _Tab(
    screen: InsightsScreen(),
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    label: 'Insights',
  );

  static final List<_Tab> _tabs = [
    _home,
    _transactions,
    _review,
    _insights,
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 720;
    final destinations = [
      for (final tab in _tabs)
        NavigationDestination(
          icon: Icon(tab.icon),
          selectedIcon: Icon(tab.selectedIcon),
          label: tab.label,
        ),
    ];
    final body = IndexedStack(
      index: _index,
      children: [for (final tab in _tabs) tab.screen],
    );

    return Scaffold(
      body: useRail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selectedIcon),
                        label: Text(tab.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: destinations,
            ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
