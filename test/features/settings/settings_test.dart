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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(WidgetTester tester) async {
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
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows Bloom Settings banner and sections', (tester) async {
    await pumpScreen(tester);

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
}
