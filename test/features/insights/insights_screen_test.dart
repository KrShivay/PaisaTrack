import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders Bloom Trends header and 6-month spend chart',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    expect(find.text('MONTH OVER MONTH'), findsOneWidget);
  });
}
