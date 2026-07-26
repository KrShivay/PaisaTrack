import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack_keystore/paisatrack_keystore.dart' as keystore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidKeystoreDatabasePassphraseProvider', () {
    const channel = MethodChannel('test/database_passphrase');
    const provider = AndroidKeystoreDatabasePassphraseProvider(
      delegate: keystore.AndroidKeystoreDatabasePassphraseProvider(
        channel: channel,
      ),
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns passphrase from platform keystore channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getPassphrase');
        return 'stored-passphrase';
      });

      final passphrase = await provider.getPassphrase();

      expect(passphrase.value, 'stored-passphrase');
    });

    test('fails closed when platform returns no passphrase', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => '');

      await expectLater(
        provider.getPassphrase(),
        throwsA(isA<StateError>()),
      );
    });

    test('clears stored passphrase through platform channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'clearPassphrase');
        return null;
      });

      await provider.clearStoredPassphrase();
    });
  });
}
