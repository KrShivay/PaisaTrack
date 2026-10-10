import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/appearance_section.dart';

class _Controller extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> setThemeChoice(AppThemeChoice choice) async {
    state = AsyncData(state.requireValue.copyWith(themeChoice: choice));
  }
}

Future<void> pumpSelector(
  WidgetTester tester, {
  Size size = const Size(402, 800),
  double textScale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSettingsControllerProvider.overrideWith(_Controller.new)],
      child: MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(36),
            child: Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(appSettingsControllerProvider);
                return settings.when(
                  data: (s) => AppearanceSectionBody(
                    settings: s,
                    isDark: dark,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows an icon, label and selected check per choice',
      (tester) async {
    await pumpSelector(tester);

    expect(find.byKey(const ValueKey('theme_choices_row')), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
    // Default is dark: exactly one check, two empty circles.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));
  });

  testWidgets('tapping a card selects it and moves the check', (tester) async {
    await pumpSelector(tester);

    await tester.tap(find.byKey(const ValueKey('theme_choice_light')));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppearanceSectionBody)),
    );
    expect(
      container.read(appSettingsControllerProvider).requireValue.themeChoice,
      AppThemeChoice.light,
    );
    final lightCard = find.byKey(const ValueKey('theme_choice_light'));
    expect(
      find.descendant(
        of: lightCard,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cards are at least 48dp tall in both layouts', (tester) async {
    await pumpSelector(tester);
    for (final choice in AppThemeChoice.values) {
      final rect = tester.getRect(
        find.byKey(ValueKey('theme_choice_${choice.name}')),
      );
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('compact 320x568 at 2x text wraps to a vertical list',
      (tester) async {
    await pumpSelector(
      tester,
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(
      find.byKey(const ValueKey('theme_choices_vertical')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    for (final choice in AppThemeChoice.values) {
      final rect = tester.getRect(
        find.byKey(ValueKey('theme_choice_${choice.name}')),
      );
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('narrow width at 1x text also uses the vertical list',
      (tester) async {
    await pumpSelector(tester, size: const Size(320, 568));
    expect(
      find.byKey(const ValueKey('theme_choices_vertical')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme renders without overflow', (tester) async {
    await pumpSelector(tester, dark: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('theme_choices_row')), findsOneWidget);
  });
}
