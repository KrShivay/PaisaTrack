import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/features/sms/sms_permission_status_card.dart';

import '../../support/fake_sms_permission_gate.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    FakeSmsPermissionGate gate,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [smsPermissionGateProvider.overrideWithValue(gate)],
        child: const MaterialApp(
          home: Scaffold(body: SmsPermissionStatusCard()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the granted state', (tester) async {
    await pumpCard(
      tester,
      FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
    );

    expect(find.text('SMS access is on'), findsOneWidget);
    expect(find.text('Allow SMS access'), findsNothing);
  });

  testWidgets('offers the runtime permission request when denied',
      (tester) async {
    await pumpCard(
      tester,
      FakeSmsPermissionGate(
        initialStatus: SmsPermissionStatus.denied,
        requestResult: SmsPermissionStatus.granted,
      ),
    );

    expect(find.text('SMS access is off'), findsOneWidget);
    await tester.tap(find.text('Allow SMS access'));
    await tester.pump();

    expect(find.text('SMS access is on'), findsOneWidget);
  });

  testWidgets('offers Android settings when permanently denied',
      (tester) async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.permanentlyDenied,
    );
    await pumpCard(tester, gate);

    expect(find.text('SMS access is blocked'), findsOneWidget);
    await tester.tap(find.text('Open app settings'));

    expect(gate.openAppSettingsCalls, 1);
  });
}
