import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// User- or device-derived secret used to unlock the encrypted database.
class DatabasePassphrase {
  const DatabasePassphrase(this.value);

  /// Plain passphrase value; callers must avoid logging or persisting it.
  final String value;
}

/// Retrieves the secret used to unlock the encrypted database.
abstract interface class DatabasePassphraseProvider {
  /// Returns the stable passphrase for this app install.
  Future<DatabasePassphrase> getPassphrase();
}

/// Android Keystore-backed database passphrase provider.
///
/// The native implementation generates the passphrase once, wraps it with an
/// Android Keystore AES key, and stores only encrypted bytes in app-private
/// storage. StrongBox is requested when the device reports support.
class AndroidKeystoreDatabasePassphraseProvider
    implements DatabasePassphraseProvider {
  const AndroidKeystoreDatabasePassphraseProvider({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/database_passphrase',
  );

  final MethodChannel _channel;

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    final passphrase = await _channel.invokeMethod<String>('getPassphrase');
    if (passphrase == null || passphrase.isEmpty) {
      throw StateError(
        'Android Keystore returned an empty database passphrase',
      );
    }

    return DatabasePassphrase(passphrase);
  }

  /// Clears the stored passphrase in debug builds for integration tests.
  @visibleForTesting
  Future<void> debugResetForTests() async {
    await _channel.invokeMethod<void>('debugResetForTests');
  }
}

/// Opens the app database through SQLCipher and fails closed if unavailable.
///
/// The passphrase is escaped before being embedded in the SQLite PRAGMA. This
/// function verifies `cipher_version` before setting the key so tests catch
/// environments that accidentally link plain SQLite.
QueryExecutor openEncryptedDatabase({
  required File file,
  required DatabasePassphrase passphrase,
}) {
  return NativeDatabase.createInBackground(
    file,
    isolateSetup: _prepareSqlCipher,
    setup: (database) {
      if (database.select('PRAGMA cipher_version').isEmpty) {
        throw StateError('SQLCipher is not available for this database');
      }

      database
          .execute("PRAGMA key = '${_escapeSqliteString(passphrase.value)}'");
    },
  );
}

Future<void> _prepareSqlCipher() async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }

  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
}

String _escapeSqliteString(String value) {
  return value.replaceAll("'", "''");
}
