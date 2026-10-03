import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/sms_provenance_relinker.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

import '../../support/fake_sms_permission_gate.dart';

class FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _FakeRelinker implements SmsProvenanceRelinker {
  int runs = 0;

  @override
  Future<SmsProvenanceRelinkResult> run() async {
    runs++;
    return const SmsProvenanceRelinkResult(
      relinked: 12,
      skippedAmbiguous: 2,
      notFound: 3,
    );
  }
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
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
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
    await tester.scrollUntilVisible(find.text('Export backup'), 300);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);

    final deleteTarget = find.text('Delete all local data');
    await tester.scrollUntilVisible(deleteTarget, 300);
    expect(deleteTarget, findsOneWidget);
  });

  testWidgets('Restore SMS sources runs the re-link and reports counts',
      (tester) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final relinker = _FakeRelinker();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyBudgetProvider.overrideWith((ref) async => null),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          smsProvenanceRelinkerProvider.overrideWith((ref) async => relinker),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final tile = find.text('Restore SMS sources');
    await tester.scrollUntilVisible(tile, 300);
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(relinker.runs, 1);
    expect(
      find.text('Restored 12 · skipped 2 unclear · 3 no longer in inbox'),
      findsOneWidget,
    );
  });

  testWidgets('Restore SMS sources asks for SMS access when denied',
      (tester) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final relinker = _FakeRelinker();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlyBudgetProvider.overrideWith((ref) async => null),
          appSettingsControllerProvider
              .overrideWith(() => FakeAppSettingsController()),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.denied),
          ),
          smsProvenanceRelinkerProvider.overrideWith((ref) async => relinker),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    final tile = find.text('Restore SMS sources');
    await tester.scrollUntilVisible(tile, 300);
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();

    expect(relinker.runs, 0);
    expect(find.text('Allow SMS access to restore sources'), findsOneWidget);
  });
}
