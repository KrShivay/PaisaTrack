import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';

class _MockGate implements SmsPermissionGate {
  SmsPermissionStatus currentStatus = SmsPermissionStatus.denied;
  bool openSettingsCalled = false;

  @override
  Future<SmsPermissionStatus> status() async => currentStatus;

  @override
  Future<SmsPermissionStatus> request() async {
    currentStatus = SmsPermissionStatus.granted;
    return currentStatus;
  }

  @override
  Future<void> openAppSettings() async {
    openSettingsCalled = true;
  }
}

void main() {
  group('SmsPermissionController recovery', () {
    test('openSettings delegates to gate', () async {
      final gate = _MockGate();
      final container = ProviderContainer(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(gate),
        ],
      );
      addTearDown(container.dispose);

      await container.read(smsPermissionControllerProvider.future);
      await container.read(smsPermissionControllerProvider.notifier).openSettings();

      expect(gate.openSettingsCalled, isTrue);
    });

    test('recheckStatus updates state from gate', () async {
      final gate = _MockGate();
      final container = ProviderContainer(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(gate),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(smsPermissionControllerProvider.future),
        SmsPermissionStatus.denied,
      );

      // Simulate user granting permission in settings
      gate.currentStatus = SmsPermissionStatus.granted;

      await container.read(smsPermissionControllerProvider.notifier).recheckStatus();

      expect(
        await container.read(smsPermissionControllerProvider.future),
        SmsPermissionStatus.granted,
      );
    });
  });
}
