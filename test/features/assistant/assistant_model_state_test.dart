import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AssistantScreen renders header, mascot, and privacy badge',
      (tester) async {
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
    expect(find.text('On-device · no internet used'), findsOneWidget);
    expect(find.text('What would you like to know?'), findsOneWidget);
  });
}
