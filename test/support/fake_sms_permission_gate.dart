import 'package:paisatrack/capture/permissions/sms_permission.dart';

/// Test double for [SmsPermissionGate] with scripted status and request results.
class FakeSmsPermissionGate implements SmsPermissionGate {
  FakeSmsPermissionGate({
    this.initialStatus = SmsPermissionStatus.denied,
    SmsPermissionStatus? requestResult,
    this.throwOnStatus = false,
  }) : requestResult = requestResult ?? SmsPermissionStatus.granted;

  final SmsPermissionStatus initialStatus;
  final SmsPermissionStatus requestResult;
  final bool throwOnStatus;

  int statusCalls = 0;
  int requestCalls = 0;

  int openAppSettingsCalls = 0;

  @override
  Future<SmsPermissionStatus> status() async {
    statusCalls++;
    if (throwOnStatus) {
      throw StateError('status unavailable');
    }
    return initialStatus;
  }

  @override
  Future<SmsPermissionStatus> request() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<void> openAppSettings() async {
    openAppSettingsCalls++;
  }
}
