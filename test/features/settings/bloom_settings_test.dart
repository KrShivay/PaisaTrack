import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

import '../../support/fake_sms_permission_gate.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> setThemeChoice(AppThemeChoice choice) async {
    state = AsyncData(state.requireValue.copyWith(themeChoice: choice));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
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
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const SettingsScreen(),
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
      expect(find.byType(BloomMascot), findsOneWidget);
      await tester.scrollUntilVisible(find.text('CATEGORIES & LEARNING'), 300);
      expect(find.text('CATEGORIES & LEARNING'), findsOneWidget);

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

    testWidgets('theme choices expose selected state and 48dp targets at 2x',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      await pumpSettings(
        tester,
        size: const Size(320, 568),
        textScale: 2,
      );
      await tester.scrollUntilVisible(find.text('Dark'), 240);

      final dark = find.bySemanticsLabel('Dark');
      await tester.ensureVisible(dark);
      await tester.pumpAndSettle();
      final darkNode = tester.getSemantics(dark);
      final darkSemanticRect = MatrixUtils.transformRect(
        darkNode.transform ?? Matrix4.identity(),
        darkNode.rect,
      );
      final darkData = darkNode.getSemanticsData();
      expect(darkData.flagsCollection.isButton, isTrue);
      expect(darkData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(darkSemanticRect.height, greaterThanOrEqualTo(48));
      expect(darkSemanticRect.width, greaterThanOrEqualTo(48));
      expect(tester.getRect(dark).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(dark).width, greaterThanOrEqualTo(48));

      final light = find.bySemanticsLabel('Light');
      await tester.ensureVisible(light);
      await tester.pumpAndSettle();
      final lightNode = tester.getSemantics(light);
      final lightSemanticRect = MatrixUtils.transformRect(
        lightNode.transform ?? Matrix4.identity(),
        lightNode.rect,
      );
      expect(
        lightNode.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
        isFalse,
      );
      final lightRect = tester.getRect(light);
      expect(lightSemanticRect.height, greaterThanOrEqualTo(48));
      expect(lightSemanticRect.width, greaterThanOrEqualTo(48));
      expect(lightRect.height, greaterThanOrEqualTo(48));
      expect(lightRect.width, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(lightRect.right - 1, lightRect.bottom - 1));
      await tester.pump();
      expect(
        tester
            .getSemantics(light)
            .getSemanticsData()
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
      semanticsDisposed = true;
    });

    testWidgets('reset-data card is a named button at its full surface',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      await pumpSettings(
        tester,
        size: const Size(320, 568),
        textScale: 2,
      );
      final label = find.text('Delete all local data');
      await tester.scrollUntilVisible(label, 240);
      final button = find.bySemanticsLabel('Delete all local data');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(button).rect.height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(button).rect.width, greaterThanOrEqualTo(48));
      final rect = tester.getRect(button);
      final viewport = tester.getRect(find.byType(ListView));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
      await tester.pumpAndSettle();
      expect(find.text('Delete all local data?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all local data?'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      semanticsDisposed = true;
    });
  });
}
