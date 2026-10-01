import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/features/onboarding/onboarding_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

import '../../support/fake_sms_permission_gate.dart';

Future<void> pumpOnboarding(
  WidgetTester tester,
  FakeSmsPermissionGate gate,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [smsPermissionGateProvider.overrideWithValue(gate)],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('shows granted confirmation when access is already granted',
      (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
    );

    expect(find.text('SMS access granted. Capture is on.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Allow SMS access'), findsNothing);
  });

  testWidgets('granted primary CTA saves onboarding completion',
      (tester) async {
    final settingsController = _RecordingSettingsController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          appSettingsControllerProvider.overrideWith(() => settingsController),
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final button = find.widgetWithText(
      FilledButton,
      'Continue to PaisaTrack',
    );
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(settingsController.savedOnboardingCompleted, isTrue);
  });

  testWidgets('denied shows the request button and grants on tap',
      (tester) async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
      requestResult: SmsPermissionStatus.granted,
    );
    await pumpOnboarding(tester, gate);

    final button = find.widgetWithText(FilledButton, 'Allow SMS access');
    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(gate.requestCalls, 1);
    expect(find.text('SMS access granted. Capture is on.'), findsOneWidget);
  });

  testWidgets('shows a busy state while the SMS permission request is pending',
      (tester) async {
    final gate = _DelayedRequestSmsPermissionGate();
    await pumpOnboarding(tester, gate);

    final button = find.widgetWithText(FilledButton, 'Allow SMS access');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Requesting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    gate.completeRequest(SmsPermissionStatus.denied);
    await tester.pump();
  });

  testWidgets(
      'permanently denied points to settings and shows Open settings button',
      (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(
        initialStatus: SmsPermissionStatus.permanentlyDenied,
      ),
    );

    expect(find.textContaining('Android is blocking us'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open settings'), findsOneWidget);
  });

  testWidgets('secondary onboarding CTA saves completion', (tester) async {
    final settingsController = _RecordingSettingsController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.denied),
          ),
          appSettingsControllerProvider.overrideWith(() => settingsController),
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final continueButton =
        find.widgetWithText(TextButton, "I'll add things myself");
    expect(continueButton, findsOneWidget);

    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();

    expect(settingsController.savedOnboardingCompleted, isTrue);
  });

  testWidgets('permanently denied still offers continue-without-SMS',
      (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(
        initialStatus: SmsPermissionStatus.permanentlyDenied,
      ),
    );

    expect(
      find.widgetWithText(TextButton, "I'll add things myself"),
      findsOneWidget,
    );
  });
}

class _RecordingSettingsController extends AppSettingsController {
  bool? savedOnboardingCompleted;

  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> setOnboardingCompleted(bool value) async {
    savedOnboardingCompleted = value;
    state = AsyncData(
      (state.valueOrNull ?? const AppSettings()).copyWith(
        onboardingCompleted: value,
      ),
    );
  }
}

class _DelayedRequestSmsPermissionGate extends FakeSmsPermissionGate {
  final _requestResult = Completer<SmsPermissionStatus>();

  void completeRequest(SmsPermissionStatus status) =>
      _requestResult.complete(status);

  @override
  Future<SmsPermissionStatus> request() {
    requestCalls++;
    return _requestResult.future;
  }
}
