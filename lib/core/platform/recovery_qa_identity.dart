import 'package:flutter/services.dart';

const recoveryQaApplicationId = 'com.paisatrack.recoveryqa';
const recoveryQaCompileTimeEnabled = bool.fromEnvironment(
  'PAISATRACK_RECOVERY_QA',
);

const _identityChannel = MethodChannel('com.paisatrack/recovery_qa_identity');

/// Verifies that recovery tests are talking to the isolated debug application.
/// A missing channel or any mismatch fails closed before test data is touched.
Future<void> verifyRecoveryQaIdentity({bool? compileTimeEnabled}) async {
  if (!(compileTimeEnabled ?? recoveryQaCompileTimeEnabled)) {
    throw const RecoveryQaIdentityException(
      'Recovery QA build flag is not enabled.',
    );
  }

  final identity = await _identityChannel.invokeMapMethod<String, Object?>(
    'identity',
  );
  if (!isValidRecoveryQaIdentity(identity)) {
    throw const RecoveryQaIdentityException(
      'Recovery QA runtime identity did not match the isolated debug app.',
    );
  }
}

bool isValidRecoveryQaIdentity(Map<String, Object?>? identity) =>
    identity?['packageName'] == recoveryQaApplicationId &&
    identity?['applicationId'] == recoveryQaApplicationId &&
    identity?['buildType'] == 'debug' &&
    identity?['debuggable'] == true &&
    identity?['recoveryQa'] == true;

class RecoveryQaIdentityException implements Exception {
  const RecoveryQaIdentityException(this.message);

  final String message;

  @override
  String toString() => 'RecoveryQaIdentityException: $message';
}
