import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/assistant/assistant_controller.dart';
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

    expect(find.text('Ask PaisaTrack'), findsWidgets);
    expect(find.text('What would you like to know?'), findsOneWidget);
    expect(find.text('How much on Swiggy this month?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
