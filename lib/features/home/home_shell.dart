import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../dev/unparsed_sms_screen.dart';
import '../review/weekly_review_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transactions_screen.dart';

/// Post-onboarding app shell: bottom navigation across the dashboard,
/// transactions, review, and settings. The developer unparsed-SMS diagnostics
/// tab is only present in debug builds (it is not a user-facing surface).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _dashboard = _Tab(
    screen: DashboardScreen(),
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
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
  static const _dev = _Tab(
    screen: UnparsedSmsScreen(),
    icon: Icons.bug_report_outlined,
    selectedIcon: Icons.bug_report,
    label: 'Dev',
  );
  static const _settings = _Tab(
    screen: SettingsScreen(),
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
  );

  static final List<_Tab> _tabs = [
    _dashboard,
    _transactions,
    _review,
    if (kDebugMode) _dev,
    _settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_index].screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        // Outlined icons inactive, filled when selected (design-system.md §6).
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
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
