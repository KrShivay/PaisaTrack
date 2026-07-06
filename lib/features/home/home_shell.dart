import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../dev/unparsed_sms_screen.dart';
import '../transactions/transactions_screen.dart';

/// Post-onboarding app shell: bottom navigation across the dashboard,
/// transactions list, and the developer unparsed-SMS diagnostics screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    TransactionsScreen(),
    UnparsedSmsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.bug_report_outlined),
            label: 'Dev',
          ),
        ],
      ),
    );
  }
}
