import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom SettingsScreen', () {
    testWidgets('renders profile banner card and section headers',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('PaisaTrack Bloom'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('CATEGORIES & LEARNING'), findsOneWidget);
      expect(find.byType(BloomMascot), findsOneWidget);

      final privacyHeader = find.text('PRIVACY & LOCAL AI');
      await tester.scrollUntilVisible(privacyHeader, 200);
      expect(privacyHeader, findsOneWidget);
    });

    testWidgets('renders theme options and destructive reset button',
        (tester) async {
      await pumpSettings(tester);

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      final deleteBtn = find.text('Delete all local data');
      await tester.scrollUntilVisible(deleteBtn, 200);
      expect(deleteBtn, findsOneWidget);
    });
  });
}
