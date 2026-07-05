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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [smsPermissionGateProvider.overrideWithValue(gate)],
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows granted confirmation when access is already granted',
      (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
    );

    expect(find.text('SMS access granted. Capture is on.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Grant SMS access'), findsNothing);
  });

  testWidgets('denied shows the request button and grants on tap',
      (tester) async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
      requestResult: SmsPermissionStatus.granted,
    );
    await pumpOnboarding(tester, gate);

    final button = find.widgetWithText(FilledButton, 'Grant SMS access');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(gate.requestCalls, 1);
    expect(find.text('SMS access granted. Capture is on.'), findsOneWidget);
  });

  testWidgets('permanently denied points to settings and hides the button',
      (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(
        initialStatus: SmsPermissionStatus.permanentlyDenied,
      ),
    );

    expect(find.textContaining('system settings'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Grant SMS access'), findsNothing);
  });

  testWidgets('status error surfaces a retry affordance', (tester) async {
    await pumpOnboarding(
      tester,
      FakeSmsPermissionGate(throwOnStatus: true),
    );

    expect(find.textContaining('Could not read'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Grant SMS access'), findsOneWidget);
  });
}
