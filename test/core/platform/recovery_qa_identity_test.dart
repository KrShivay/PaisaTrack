import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';

const _identityChannel = MethodChannel('com.paisatrack/recovery_qa_identity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_identityChannel, null);
  });

  test('rejects the default build before querying native identity', () async {
    await expectLater(
      verifyRecoveryQaIdentity(compileTimeEnabled: false),
      throwsA(isA<RecoveryQaIdentityException>()),
    );
  });

  test('accepts only the exact isolated debug application identity', () {
    expect(
      isValidRecoveryQaIdentity(const {
        'packageName': 'com.paisatrack.recoveryqa',
        'applicationId': 'com.paisatrack.recoveryqa',
        'buildType': 'debug',
        'debuggable': true,
        'recoveryQa': true,
      }),
      isTrue,
    );
  });

  test('awaits a positive native identity attestation', () async {
    var queried = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_identityChannel, (call) async {
      queried = true;
      expect(call.method, 'identity');
      return const {
        'packageName': 'com.paisatrack.recoveryqa',
        'applicationId': 'com.paisatrack.recoveryqa',
        'buildType': 'debug',
        'debuggable': true,
        'recoveryQa': true,
      };
    });

    await verifyRecoveryQaIdentity(compileTimeEnabled: true);

    expect(queried, isTrue);
  });

  test('rejects package, variant, debuggable, or QA-flag mismatches', () {
    const valid = <String, Object?>{
      'packageName': 'com.paisatrack.recoveryqa',
      'applicationId': 'com.paisatrack.recoveryqa',
      'buildType': 'debug',
      'debuggable': true,
      'recoveryQa': true,
    };

    for (final mismatch in <Map<String, Object?>>[
      {...valid, 'packageName': 'com.paisatrack'},
      {...valid, 'applicationId': 'com.paisatrack'},
      {...valid, 'buildType': 'release'},
      {...valid, 'debuggable': false},
      {...valid, 'recoveryQa': false},
    ]) {
      expect(isValidRecoveryQaIdentity(mismatch), isFalse);
    }
    expect(isValidRecoveryQaIdentity(null), isFalse);
  });

  test('fails closed when the QA-only identity channel is missing', () async {
    await expectLater(
      verifyRecoveryQaIdentity(compileTimeEnabled: true),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('rejects a production package before callers can continue', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _identityChannel,
      (call) async => const {
        'packageName': 'com.paisatrack',
        'applicationId': 'com.paisatrack',
        'buildType': 'release',
        'debuggable': false,
        'recoveryQa': false,
      },
    );

    await expectLater(
      verifyRecoveryQaIdentity(compileTimeEnabled: true),
      throwsA(isA<RecoveryQaIdentityException>()),
    );
  });
}
