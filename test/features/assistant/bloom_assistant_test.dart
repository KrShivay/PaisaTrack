import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/app_tokens.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/prompt_catalogue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAssistant(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
        ],
        child: const MaterialApp(
          home: AssistantScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom AssistantScreen', () {
    testWidgets('renders Ask PaisaTrack header, mascot, and preset chips',
        (tester) async {
      await pumpAssistant(tester);

      expect(find.text('Ask PaisaTrack'), findsOneWidget);
      expect(find.text(assistantPromptQuestions.first), findsOneWidget);
      expect(find.text(assistantPromptQuestions.take(4).last), findsOneWidget);
      expect(find.byType(BloomMascot), findsWidgets);
    });

    testWidgets('renders bottom input bar with send button', (tester) async {
      await pumpAssistant(tester);

      expect(find.text('Ask anything about your money…'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      final composer = tester.widget<Container>(
        find.byKey(const ValueKey('assistant_composer')),
      );
      final composerDecoration = composer.decoration! as BoxDecoration;
      expect(composerDecoration.color, AppColorTokens.bloomDarkCard);
      expect(
        composerDecoration.border,
        Border.all(color: AppColorTokens.bloomDarkOutline),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('assistant_composer'))).height,
        52,
      );

      final sendButton = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('assistant_send_button')),
          matching: find.byType(Container),
        ),
      );
      final sendDecoration = sendButton.decoration! as BoxDecoration;
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byKey(const ValueKey('assistant_send_button')),
                matching: find.byType(Container),
              ),
            )
            .width,
        40,
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byKey(const ValueKey('assistant_send_button')),
                matching: find.byType(Container),
              ),
            )
            .height,
        40,
      );
      expect(
        sendDecoration.gradient,
        const LinearGradient(
          colors: [
            AppColorTokens.bloomEmerald,
            AppColorTokens.bloomEmeraldDeep,
          ],
        ),
      );
    });
  });
}
