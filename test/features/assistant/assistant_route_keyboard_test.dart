import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _StubAssistantController extends AssistantController {
  _StubAssistantController({required super.runtime, required super.database});

  final askedQuestions = <String>[];
  String? response;

  @override
  Future<String> ask(String question) async {
    askedQuestions.add(question);
    return response ?? 'Answer: $question';
  }
}

Future<void> _pumpAskRoute(
  WidgetTester tester, {
  required AppDatabase database,
  required AssistantController controller,
  Size viewport = const Size(320, 568),
  double textScale = 2,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  tester.view.viewInsets = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        assistantControllerProvider.overrideWith((ref) async => controller),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: SizedBox(
              width: viewport.width,
              height: mediaQuery.size.height,
              child: child!,
            ),
          );
        },
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  showBloomFullScreenSheet<void>(
                    context: context,
                    showBack: false,
                    showClose: false,
                    backgroundColor: const Color(0xFF0E0C1A),
                    headerBuilder: AssistantScreen.sheetHeader,
                    avoidKeyboard: true,
                    builder: (_) =>
                        const AssistantScreen(showSheetHeader: false),
                  );
                },
                child: const Text('Open Ask'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Ask'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late _StubAssistantController controller;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    controller = _StubAssistantController(
      runtime: const NoopLlmRuntime(LlmUnavailableReason.modelAbsent),
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets(
    'Ask full-screen route composer fits compact 2x text baseline',
    (tester) async {
      await _pumpAskRoute(
        tester,
        database: database,
        controller: controller,
      );

      final composer = find.byKey(const ValueKey('assistant_composer'));
      expect(composer, findsOneWidget);
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(568));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ask prompt suggestions meet 48dp at 1x, 1.5x, and wrap at 2x',
    (tester) async {
      const question = 'How much did I spend on food this month?';
      for (final scale in [1.0, 1.5, 2.0]) {
        await _pumpAskRoute(
          tester,
          database: database,
          controller: controller,
          viewport: const Size(434, 964),
          textScale: scale,
        );

        final suggestionText = find.text(question);
        final suggestion = find.ancestor(
          of: suggestionText,
          matching: find.byType(InkWell),
        );
        expect(suggestion, findsOneWidget, reason: 'text scale $scale');
        expect(
          tester.getRect(suggestion).height,
          greaterThanOrEqualTo(48),
          reason: 'text scale $scale must retain a 48dp target',
        );
        if (scale == 2) {
          expect(tester.getRect(suggestionText).height, greaterThan(48));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      await _pumpAskRoute(
        tester,
        database: database,
        controller: controller,
        viewport: const Size(964, 434),
        textScale: 1,
      );
      final landscapeSuggestion = find.ancestor(
        of: find.text(question),
        matching: find.byType(InkWell),
      );
      expect(landscapeSuggestion, findsOneWidget);
      expect(
        tester.getRect(landscapeSuggestion).height,
        greaterThanOrEqualTo(48),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest answer stays visible before compact landscape suggestions',
    (tester) async {
      controller.response = [
        'You spent ₹3,494.57 on Food & Dining in October 2026 across 14 transactions.',
        'How this was counted: Spending · Food & Dining',
        'Matched transactions are listed separately by currency.',
      ].join('\n');
      await _pumpAskRoute(
        tester,
        database: database,
        controller: controller,
        viewport: const Size(964, 434),
        textScale: 2,
      );

      await tester.enterText(find.byType(TextField).last, 'October spending');
      await tester.tap(find.byKey(const ValueKey('assistant_send_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final answer = find.text(controller.response!);
      final suggestions = find.byKey(const ValueKey('assistant_prompt_list'));
      expect(answer, findsOneWidget);
      expect(suggestions, findsOneWidget);
      expect(
        tester.getRect(answer).bottom,
        lessThanOrEqualTo(tester.getRect(suggestions).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Try asking heading aligns with the suggestion cards', (
    tester,
  ) async {
    await _pumpAskRoute(
      tester,
      database: database,
      controller: controller,
      viewport: const Size(434, 964),
      textScale: 1,
    );

    await tester.enterText(find.byType(TextField).last, 'Show my spending');
    await tester.tap(find.byKey(const ValueKey('assistant_send_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final heading = tester.getRect(find.text('Try asking'));
    final firstSuggestion = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('assistant_prompt_list')),
            matching: find.byType(TextButton),
          )
          .first,
    );
    expect(heading.left, firstSuggestion.left);
  });

  testWidgets('Ask composer keeps a 48dp field at landscape 2x text',
      (tester) async {
    await _pumpAskRoute(
      tester,
      database: database,
      controller: controller,
      viewport: const Size(964, 434),
      textScale: 2,
    );

    final composerField = find.descendant(
      of: find.byKey(const ValueKey('assistant_composer')),
      matching: find.byType(TextField),
    );
    expect(composerField, findsOneWidget);
    expect(tester.getRect(composerField).height, greaterThanOrEqualTo(48));
    final semantics = tester.ensureSemantics();
    try {
      final semanticField = find.bySemanticsLabel(
        'Ask anything about your money…',
      );
      expect(semanticField, findsOneWidget);
      expect(tester.getRect(semanticField).height, greaterThanOrEqualTo(48));
    } finally {
      semantics.dispose();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ask route keeps its header, suggestions, and composer above a full-window IME',
    (tester) async {
      await _pumpAskRoute(
        tester,
        database: database,
        controller: controller,
        textScale: 1.5,
      );

      final composer = find.byKey(const ValueKey('assistant_composer'));
      await tester.tap(
        find.descendant(
          of: composer,
          matching: find.byType(TextField),
        ),
      );
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      const visibleBottom = 348.0;
      final close = find.byTooltip('Close');
      final firstSuggestion =
          find.text('How much did I spend on food this month?');

      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(visibleBottom));
      expect(close, findsOneWidget);
      expect(tester.getRect(close).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(visibleBottom));
      expect(find.text('On-device · no internet used'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
      expect(firstSuggestion, findsOneWidget);
      await tester.ensureVisible(firstSuggestion);
      expect(
        tester.getRect(firstSuggestion).bottom,
        lessThanOrEqualTo(visibleBottom),
      );
      expect(MediaQuery.viewInsetsOf(tester.element(composer)).bottom, 220);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'Ask full-screen route fits the keyboard-resized compact 2x viewport',
    (tester) async {
      await _pumpAskRoute(
        tester,
        database: database,
        controller: controller,
      );

      const question = 'Route transcript scroll check';
      final composerField = find.descendant(
        of: find.byKey(const ValueKey('assistant_composer')),
        matching: find.byType(TextField),
      );
      await tester.enterText(composerField, question);
      await tester.tap(find.byKey(const ValueKey('assistant_send_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        controller.askedQuestions,
        contains(question),
      );

      // Android adjustResize changes the available viewport from 568dp to
      // 348dp. Keep viewInsets at zero so the keyboard area is counted once.
      tester.view.physicalSize = const Size(320, 348);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Answer: $question'), findsOneWidget);

      final composer = find.byKey(const ValueKey('assistant_composer'));
      expect(composer, findsOneWidget);
      expect(
        MediaQuery.sizeOf(tester.element(composer)).height,
        lessThanOrEqualTo(348),
      );
      expect(MediaQuery.viewInsetsOf(tester.element(composer)).bottom, 0);
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(348));
      expect(
        tester.getRect(find.text('Ask PaisaTrack')).height,
        lessThanOrEqualTo(40),
      );
      expect(find.text('On-device · no internet used'), findsNothing);
      expect(
        tester.getSize(find.byTooltip('Close')).height,
        greaterThanOrEqualTo(48),
      );

      final messageList = find.ancestor(
        of: find.text('Answer: $question'),
        matching: find.byType(ListView),
      );
      expect(messageList, findsOneWidget);
      final transcriptScrollable = find.ancestor(
        of: find.text('Answer: $question'),
        matching: find.byType(Scrollable),
      );
      expect(transcriptScrollable, findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(transcriptScrollable)
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      final transcriptState =
          tester.state<ScrollableState>(transcriptScrollable);
      transcriptState.position.jumpTo(transcriptState.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(question), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
