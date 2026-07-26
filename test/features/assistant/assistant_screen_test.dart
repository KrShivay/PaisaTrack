import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

void main() {
  late AppDatabase db;
  late AssistantController controller;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    controller = _StubAssistantController(
      runtime: const NoopLlmRuntime(LlmUnavailableReason.modelAbsent),
      database: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidget() {
    return ProviderScope(
      overrides: [
        assistantControllerProvider.overrideWith((ref) async => controller),
      ],
      child: const MaterialApp(home: AssistantScreen()),
    );
  }

  testWidgets('shows privacy message, suggestions, and safe-area input',
      (tester) async {
    await tester.pumpWidget(createWidget());

    expect(
      find.text('Your questions and financial data stay on this device.'),
      findsOneWidget,
    );
    expect(find.text('Try asking'), findsOneWidget);
    expect(
      find.text('How much did I spend on food this month?'),
      findsOneWidget,
    );
    expect(find.text('Spending'), findsWidgets);
    expect(find.text('Subscriptions & Bills'), findsWidgets);
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('filters questions when category chip is selected',
      (tester) async {
    await tester.pumpWidget(createWidget());

    // Filter by Subscriptions category chip in welcome view
    final subChip = find.widgetWithText(FilterChip, 'Subscriptions & Bills');
    expect(subChip, findsOneWidget);
    await tester.tap(subChip);
    await tester.pumpAndSettle();

    expect(
      find.text('What subscriptions renew this week?'),
      findsOneWidget,
    );
    // Food question from spending category should be hidden when filtered to Subscriptions
    expect(
      find.text('How much did I spend on food this month?'),
      findsNothing,
    );
  });

  testWidgets(
      'retains persistent question suggestion tray when message history exists',
      (tester) async {
    await tester.pumpWidget(createWidget());

    // Tap a suggestion question to initiate chat
    final foodQuestion =
        find.text('How much did I spend on food this month?').first;
    await tester.tap(foodQuestion);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The user's question is displayed in chat history & chip tray
    expect(find.text('How much did I spend on food this month?'), findsWidgets);

    // The persistent question tray with category and action chips remains above the input field
    final allChip = find.widgetWithText(FilterChip, 'All Questions');
    expect(allChip, findsOneWidget);

    // Switch tray category to Subscriptions & Bills
    final subTrayCategory =
        find.widgetWithText(FilterChip, 'Subscriptions & Bills').first;
    await tester.tap(subTrayCategory);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final chipQuestion = find.widgetWithText(
      ActionChip,
      'What subscriptions renew this week?',
    );
    expect(chipQuestion, findsOneWidget);

    // Tapping another chip sends it into the chat stream
    await tester.tap(chipQuestion);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('What subscriptions renew this week?'),
      findsWidgets,
    );
  });
}

class _StubAssistantController extends AssistantController {
  _StubAssistantController({
    required super.runtime,
    required super.database,
  });

  @override
  Future<String> ask(String text) async => 'Test answer for $text';
}
