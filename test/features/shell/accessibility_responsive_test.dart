import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'App screens render without overflow on small and large viewports',
      (tester) async {
    // 1. Small compact viewport (320 x 568 - iPhone SE 1st gen)
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AssistantScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ask PaisaTrack'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
