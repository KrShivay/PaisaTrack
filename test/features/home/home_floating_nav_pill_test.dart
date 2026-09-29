import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/home/home_shell.dart';

void main() {
  testWidgets('compact navigation keeps accessible 48dp tab targets',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => HomeFloatingNavPill(
                  currentIndex: selectedIndex,
                  destinations: const [
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
                  ],
                  onTabSelected: (index) =>
                      setState(() => selectedIndex = index),
                  onAskTapped: () {},
                  isDark: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final pill = find.byKey(const ValueKey('floating_navigation_pill'));
    expect(tester.getSize(pill), const Size(280, 64));
    final activity = find.descendant(
      of: pill,
      matching: find.bySemanticsLabel('Activity'),
    );
    expect(tester.getSize(activity), const Size(48, 48));
    await tester.tap(activity);
    await tester.pump();
    expect(selectedIndex, 1);
    expect(tester.takeException(), isNull);
  });
}
