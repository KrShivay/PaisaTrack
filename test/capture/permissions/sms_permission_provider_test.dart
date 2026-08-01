import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';

import '../../support/fake_sms_permission_gate.dart';

void main() {
  ProviderContainer containerWith(FakeSmsPermissionGate gate) {
    final container = ProviderContainer(
      overrides: [smsPermissionGateProvider.overrideWithValue(gate)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('build reflects the current status without prompting', () async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
    );
    final container = containerWith(gate);

    final status = await container.read(smsPermissionControllerProvider.future);

    expect(status, SmsPermissionStatus.denied);
    expect(gate.statusCalls, 1);
    expect(gate.requestCalls, 0);
  });

  test('request publishes the granted outcome', () async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
      requestResult: SmsPermissionStatus.granted,
    );
    final container = containerWith(gate);
    await container.read(smsPermissionControllerProvider.future);

    await container.read(smsPermissionControllerProvider.notifier).request();

    expect(
      container.read(smsPermissionControllerProvider).value,
      SmsPermissionStatus.granted,
    );
    expect(gate.requestCalls, 1);
  });

  test('request surfaces a denied outcome instead of throwing', () async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.denied,
      requestResult: SmsPermissionStatus.permanentlyDenied,
    );
    final container = containerWith(gate);
    await container.read(smsPermissionControllerProvider.future);

    await container.read(smsPermissionControllerProvider.notifier).request();

    expect(
      container.read(smsPermissionControllerProvider).value,
      SmsPermissionStatus.permanentlyDenied,
    );
  });

  test('recheckStatus publishes a permission change made in system settings',
      () async {
    final gate = FakeSmsPermissionGate(
      initialStatus: SmsPermissionStatus.permanentlyDenied,
    );
    final container = containerWith(gate);
    await container.read(smsPermissionControllerProvider.future);

    gate.currentStatus = SmsPermissionStatus.granted;
    await container
        .read(smsPermissionControllerProvider.notifier)
        .recheckStatus();

    expect(
      container.read(smsPermissionControllerProvider).value,
      SmsPermissionStatus.granted,
    );
    expect(gate.statusCalls, 2);
  });

  test('build error is captured as AsyncError, not a crash', () async {
    final gate = FakeSmsPermissionGate(throwOnStatus: true);
    final container = containerWith(gate);

    await expectLater(
      container.read(smsPermissionControllerProvider.future),
      throwsA(isA<StateError>()),
    );
    expect(container.read(smsPermissionControllerProvider).hasError, isTrue);
  });

  test('fromName maps unknown or null names defensively', () {
    expect(
      SmsPermissionStatus.fromName('granted'),
      SmsPermissionStatus.granted,
    );
    expect(SmsPermissionStatus.fromName(null), SmsPermissionStatus.unknown);
    expect(SmsPermissionStatus.fromName('bogus'), SmsPermissionStatus.unknown);
  });
}
