import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/home/home_shell.dart';

void main() {
  Future<void> pumpPill(
    WidgetTester tester, {
    required int badgeCount,
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: HomeFloatingNavPill(
            currentIndex: 0,
            trendsNewCount: badgeCount,
            destinations: const [
              HomeNavigationDestination(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
              ),
              HomeNavigationDestination(
                label: 'Activity',
                icon: Icons.list,
                selectedIcon: Icons.list,
              ),
              HomeNavigationDestination(
                label: 'Sort',
                icon: Icons.sort,
                selectedIcon: Icons.sort,
              ),
              HomeNavigationDestination(
                label: 'Trends',
                icon: Icons.insights_outlined,
                selectedIcon: Icons.insights,
              ),
            ],
            onTabSelected: (_) {},
            onAskTapped: () {},
            isDark: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Trends nav shows the new-item count accessibly', (tester) async {
    await pumpPill(tester, badgeCount: 2);

    expect(find.text('2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Trends, 2 new insights',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '2',
      ),
      findsNothing,
    );
  });

  testWidgets('zero new items leaves the Trends label unchanged',
      (tester) async {
    await pumpPill(tester, badgeCount: 0);

    expect(find.text('2'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Trends',
      ),
      findsOneWidget,
    );
  });

  testWidgets('scales large badge text at 320dp and keeps 48dp targets',
      (tester) async {
    await pumpPill(
      tester,
      badgeCount: 12345,
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(find.text('999+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final destination in find.byType(InkWell).evaluate()) {
      expect(
        tester.getSize(find.byWidget(destination.widget)),
        const Size(48, 48),
      );
    }
  });
}
