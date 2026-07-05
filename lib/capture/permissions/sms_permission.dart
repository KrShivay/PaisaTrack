import 'package:flutter/services.dart';

/// Runtime state of the Android SMS read/receive permissions.
///
/// [permanentlyDenied] means the OS will no longer show the system prompt, so
/// the UI must direct the user to app settings instead of re-requesting.
enum SmsPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  unknown;

  /// True only when both RECEIVE_SMS and READ_SMS have been granted.
  bool get isGranted => this == SmsPermissionStatus.granted;

  static SmsPermissionStatus fromName(String? name) {
    return SmsPermissionStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => SmsPermissionStatus.unknown,
    );
  }
}

/// Reads and requests the SMS permissions the capture pipeline depends on.
///
/// The interface exists so widgets and providers can be tested with a fake
/// gate, without touching the platform channel or a real device.
abstract interface class SmsPermissionGate {
  /// Returns the current permission status without prompting the user.
  Future<SmsPermissionStatus> status();

  /// Shows the system permission prompt and resolves with the outcome.
  Future<SmsPermissionStatus> request();
}

/// Platform-channel implementation backed by the Android host.
///
/// Mirrors the channel convention used by the database passphrase provider so
/// all native capabilities are reached the same way.
class PlatformSmsPermissionGate implements SmsPermissionGate {
  const PlatformSmsPermissionGate({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/sms_permissions',
  );

  final MethodChannel _channel;

  @override
  Future<SmsPermissionStatus> status() async {
    final name = await _channel.invokeMethod<String>('status');
    return SmsPermissionStatus.fromName(name);
  }

  @override
  Future<SmsPermissionStatus> request() async {
    final name = await _channel.invokeMethod<String>('request');
    return SmsPermissionStatus.fromName(name);
  }
}
