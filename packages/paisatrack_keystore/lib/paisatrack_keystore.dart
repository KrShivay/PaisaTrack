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

  /// Creates an isolated key slot for a staged database generation. The
  /// existing database key and wrapped passphrase remain unchanged.
  Future<DatabasePassphrase> createGenerationPassphrase(
    String generationId,
  ) async {
    final value = await _channel.invokeMethod<String>(
      'createGenerationPassphrase',
      {'generationId': generationId},
    );
    if (value == null || value.isEmpty) {
      throw StateError('Android Keystore returned an empty recovery key');
    }
    return DatabasePassphrase(value);
  }

  Future<DatabasePassphrase> getGenerationPassphrase(
    String generationId,
  ) async {
    final value = await _channel.invokeMethod<String>(
      'getGenerationPassphrase',
      {'generationId': generationId},
    );
    if (value == null || value.isEmpty) {
      throw StateError('Android Keystore returned an empty recovery key');
    }
    return DatabasePassphrase(value);
  }

  Future<void> deleteGenerationPassphrase(String generationId) =>
      _channel.invokeMethod<void>('deleteGenerationPassphrase', {
        'generationId': generationId,
      });

  Future<Set<String>> getGenerationIds() async =>
      ((await _channel.invokeListMethod<String>('getGenerationIds')) ??
              const <String>[])
          .toSet();

  Future<String?> getActiveGenerationId() =>
      _channel.invokeMethod<String>('getActiveGenerationId');

  Future<Set<String>> getStagingGenerationIds() async =>
      ((await _channel.invokeListMethod<String>('getStagingGenerationIds')) ??
              const <String>[])
          .toSet();

  Future<void> activateGeneration(String generationId) => _channel
      .invokeMethod<void>('activateGeneration', {'generationId': generationId});

  Future<void> clearAllGenerationPassphrases() =>
      _channel.invokeMethod<void>('clearAllGenerationPassphrases');

  Future<void> debugResetForTests() async {
    await _channel.invokeMethod<void>('debugResetForTests');
  }
}
