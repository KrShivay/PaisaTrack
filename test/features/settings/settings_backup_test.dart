import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SettingsScreen renders appearance, data & backup options',
      (tester) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyBudgetProvider.overrideWith((ref) async => null),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Show paise'), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Delete all local data'), findsOneWidget);
  });
}
