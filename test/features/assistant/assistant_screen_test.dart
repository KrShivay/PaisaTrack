import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/assistant/prompt_catalogue.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _StubAssistantController extends AssistantController {
  _StubAssistantController({
    required super.runtime,
    required super.database,
  });

  @override
  Future<String> ask(String question) async {
    return 'Stub answer for: $question';
  }
}

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

  Widget createWidget(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        assistantControllerProvider.overrideWith((ref) async => controller),
      ],
      child: const MaterialApp(home: AssistantScreen()),
    );
  }

  testWidgets('shows Ask PaisaTrack preset suggestions and input bar',
      (tester) async {
    await tester.pumpWidget(createWidget(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ask PaisaTrack'), findsOneWidget);
    expect(find.text('What would you like to know?'), findsOneWidget);
    expect(find.text(assistantPromptQuestions.first), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assistant_prompt_search_field')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('uses one dark sheet header in a light theme', (tester) async {
    await tester.pumpWidget(
      createWidget(tester),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ask PaisaTrack'), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('assistant_sheet_surface')),
          )
          .color,
      const Color(0xFF0E0C1A),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('searches the catalogue by group or question text',
      (tester) async {
    await tester.pumpWidget(createWidget(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Spending'), findsOneWidget);

    final search = find.byKey(
      const ValueKey('assistant_prompt_search_field'),
    );
    await tester.enterText(search, 'subscription');
    await tester.pump();

    expect(find.text('Subscriptions & Bills'), findsOneWidget);
    expect(find.text('What subscriptions renew this week?'), findsOneWidget);
    expect(find.text('Spending'), findsNothing);

    await tester.enterText(search, 'no matching question');
    await tester.pump();
    expect(find.text('No matching questions.'), findsOneWidget);
  });

  testWidgets('shows three rotating prompt chips after a conversation starts',
      (tester) async {
    await tester.pumpWidget(createWidget(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
      find.byType(TextField).last,
      'How much did I spend?',
    );
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ActionChip), findsNWidgets(3));
    final firstSet = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((chip) => (chip.label as Text).data)
        .toList();

    await tester
        .tap(find.byKey(const ValueKey('assistant_prompt_chip_rotate')));
    await tester.pump();
    final secondSet = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((chip) => (chip.label as Text).data)
        .toList();

    expect(secondSet, isNot(equals(firstSet)));
  });
}
