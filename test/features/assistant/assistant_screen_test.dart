import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';

void main() {
  testWidgets('shows privacy message, suggestions, and safe-area input',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AssistantScreen()),
      ),
    );

    expect(
      find.text('Your questions and financial data stay on this device.'),
      findsOneWidget,
    );
    expect(find.text('Try asking'), findsOneWidget);
    expect(
      find.text('How much did I spend on food this month?'),
      findsOneWidget,
    );
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });
}
