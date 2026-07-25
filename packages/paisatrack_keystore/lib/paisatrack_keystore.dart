import 'package:flutter/services.dart';

/// User- or device-derived secret used to unlock the encrypted database.
class DatabasePassphrase {
  const DatabasePassphrase(this.value);

  /// Plain passphrase value; callers must never log or persist it.
  final String value;
}

/// Android Keystore-backed database passphrase provider.
///
/// The native implementation generates a passphrase once, wraps it with an
/// Android Keystore AES key, and stores only encrypted bytes in app-private
/// storage. StrongBox is requested when the device reports support.
class AndroidKeystoreDatabasePassphraseProvider {
  const AndroidKeystoreDatabasePassphraseProvider({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/database_passphrase',
  );

  final MethodChannel _channel;

  Future<DatabasePassphrase> getPassphrase() async {
    final passphrase = await _channel.invokeMethod<String>('getPassphrase');
    if (passphrase == null || passphrase.isEmpty) {
      throw StateError(
        'Android Keystore returned an empty database passphrase',
      );
    }

    return DatabasePassphrase(passphrase);
  }

  Future<void> clearStoredPassphrase() async {
    await _channel.invokeMethod<void>('clearPassphrase');
  }

  Future<void> debugResetForTests() async {
    await _channel.invokeMethod<void>('debugResetForTests');
  }
}
