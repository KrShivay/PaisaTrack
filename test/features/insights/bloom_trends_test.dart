import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTrends(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: InsightsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom Trends / InsightsScreen', () {
    testWidgets('renders title, Recurring button, and 6-month trend chart',
        (tester) async {
      await pumpTrends(tester);

      expect(find.text('Trends'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
      expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    });

    testWidgets('renders Month-over-Month comparison card', (tester) async {
      await pumpTrends(tester);

      expect(find.text('MONTH OVER MONTH'), findsOneWidget);
      expect(find.textContaining('spent so far'), findsOneWidget);
    });
  });
}
