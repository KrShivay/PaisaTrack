import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_lifecycle.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/features/sms/sms_permission_status_card.dart';
import '../../support/fake_sms_permission_gate.dart';

void main() {
  testWidgets('rechecks SMS permission when the app resumes', (tester) async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(gate),
        ],
        child: const SmsPermissionLifecycleRefresher(
          child: MaterialApp(
            home: Scaffold(body: SmsPermissionStatusCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('SMS access is off'), findsOneWidget);

    gate.currentStatus = SmsPermissionStatus.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SMS access is on'), findsOneWidget);
    expect(gate.statusCalls, greaterThanOrEqualTo(2));
  });
}
