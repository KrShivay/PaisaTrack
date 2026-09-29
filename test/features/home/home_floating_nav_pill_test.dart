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

  for (final width in [402.0, 600.0]) {
    for (final textScale in [1.5, 2.0]) {
      testWidgets(
        'large-text navigation fits ${width.toInt()}px at ${textScale}x',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          var askTaps = 0;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: width - 40,
                    child: HomeFloatingNavPill(
                      currentIndex: 1,
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
                      onTabSelected: (_) {},
                      onAskTapped: () => askTaps++,
                      isDark: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final activity = find.bySemanticsLabel('Activity');
          expect(
            tester.getSemantics(activity),
            matchesSemantics(
              label: 'Activity',
              isSelected: true,
              hasSelectedState: true,
              isButton: true,
              isFocusable: true,
              hasFocusAction: true,
              hasTapAction: true,
            ),
          );
          expect(tester.getSize(activity), const Size(48, 48));
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('floating_navigation_pill')),
              matching: find.text('Activity'),
            ),
            findsNothing,
          );

          final ask = find.bySemanticsLabel('Ask PaisaTrack');
          expect(tester.getSize(ask), const Size(48, 48));
          await tester.tap(ask);
          await tester.pump();
          expect(askTaps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
