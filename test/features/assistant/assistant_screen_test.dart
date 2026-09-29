import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/assistant/prompt_catalogue.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _StubAssistantController extends AssistantController {
  _StubAssistantController({required super.runtime, required super.database});

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

  Widget createWidget(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    double textScale = 1,
    double bottomInset = 0,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        assistantControllerProvider.overrideWith((ref) async => controller),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size.width,
              height: size.height - bottomInset,
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(textScale),
                  viewInsets: EdgeInsets.only(bottom: bottomInset),
                ),
                child: child!,
              ),
            ),
          );
        },
        home: const AssistantScreen(),
      ),
    );
  }

  testWidgets('shows Ask PaisaTrack preset suggestions and input bar', (
    tester,
  ) async {
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
    await tester.pumpWidget(createWidget(tester));
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

  testWidgets('searches the catalogue by group or question text', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Spending'), findsOneWidget);

    final search = find.byKey(const ValueKey('assistant_prompt_search_field'));
    await tester.enterText(search, 'subscription');
    await tester.pump();

    expect(find.text('Subscriptions & Bills'), findsOneWidget);
    expect(find.text('What subscriptions renew this week?'), findsOneWidget);
    expect(find.text('Spending'), findsNothing);

    await tester.enterText(search, 'no matching question');
    await tester.pump();
    expect(find.text('No matching questions.'), findsOneWidget);
  });

  testWidgets('shows three full-text rotating prompt rows after a question', (
    tester,
  ) async {
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

    expect(find.byKey(const ValueKey('assistant_prompt_list')), findsOneWidget);
    final firstSet = assistantPromptQuestions.skip(3).take(3).toList();
    final semantics = tester.ensureSemantics();
    for (final question in firstSet) {
      final button = find.byKey(
        ValueKey('assistant_prompt_list_item_$question'),
      );
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(of: button, matching: find.text(question)),
        findsOneWidget,
      );
      final node = tester.getSemantics(button);
      expect(node.label, question);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    semantics.dispose();

    await tester.tap(
      find.byKey(const ValueKey('assistant_prompt_chip_rotate')),
    );
    await tester.pump();
    final secondSet = assistantPromptQuestions.skip(6).take(3).toList();

    expect(secondSet, isNot(equals(firstSet)));
    for (final question in secondSet) {
      expect(
        find.byKey(ValueKey('assistant_prompt_list_item_$question')),
        findsOneWidget,
      );
    }
  });

  testWidgets('tapping a prompt sends its full text and rotates the list', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final question = assistantPromptQuestions[3];
    await tester.enterText(find.byType(TextField).last, 'Start the chat');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(
      find.byKey(ValueKey('assistant_prompt_list_item_$question')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(question), findsOneWidget);
    expect(find.text('Stub answer for: $question'), findsOneWidget);
    for (final nextQuestion in assistantPromptQuestions.skip(6).take(3)) {
      expect(
        find.byKey(ValueKey('assistant_prompt_list_item_$nextQuestion')),
        findsOneWidget,
      );
    }
  });

  testWidgets('long prompt wraps completely at 320dp and 2x text', (
    tester,
  ) async {
    await tester.pumpWidget(
      createWidget(tester, size: const Size(320, 568), textScale: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(find.byType(TextField).last, 'Start the chat');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final question = assistantPromptQuestions[3];
    final questionText = find.descendant(
      of: find.byKey(ValueKey('assistant_prompt_list_item_$question')),
      matching: find.text(question),
    );
    final button = find.byKey(ValueKey('assistant_prompt_list_item_$question'));
    expect(questionText, findsOneWidget);
    final text = tester.widget<Text>(questionText);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(tester.getSize(button).height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prompt list and composer fit a keyboard-resized narrow sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      createWidget(tester, size: const Size(320, 568), bottomInset: 220),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(find.byType(TextField).last, 'Start the chat');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('assistant_prompt_list')), findsOneWidget);
    expect(find.byKey(const ValueKey('assistant_composer')), findsOneWidget);
    final lastQuestion = assistantPromptQuestions[5];
    final lastPrompt = find.byKey(
      ValueKey('assistant_prompt_list_item_$lastQuestion'),
    );
    await tester.ensureVisible(lastPrompt);
    await tester.pump(const Duration(milliseconds: 200));
    final listRect = tester.getRect(
      find.byKey(const ValueKey('assistant_prompt_list_scroll')),
    );
    final lastPromptRect = tester.getRect(lastPrompt);
    expect(lastPromptRect.top, greaterThanOrEqualTo(listRect.top));
    expect(lastPromptRect.bottom, lessThanOrEqualTo(listRect.bottom));
    expect(tester.takeException(), isNull);
    final composerRect = tester.getRect(
      find.byKey(const ValueKey('assistant_composer')),
    );
    expect(composerRect.bottom, lessThanOrEqualTo(568 - 220));
  });
}
