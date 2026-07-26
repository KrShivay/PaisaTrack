import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/features/onboarding/onboarding_screen.dart';

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

  testWidgets('denied offers continue-without-SMS and sets the flag',
      (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.denied),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const OnboardingScreen();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(capturedRef.read(continueWithoutSmsProvider), isFalse);

    final continueButton =
        find.widgetWithText(TextButton, "I'll add things myself");
    expect(continueButton, findsOneWidget);

    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();

    // The routing flag flips so PaisaTrackApp shows HomeShell instead of
    // trapping the user on onboarding (S1 lockout fix).
    expect(capturedRef.read(continueWithoutSmsProvider), isTrue);
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
