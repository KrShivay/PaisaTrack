import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'package:paisatrack_keystore/paisatrack_keystore.dart' as keystore;

/// Operational error when the database passphrase cannot be decrypted against an existing DB.
class DatabaseKeyLostError implements Exception {
  const DatabaseKeyLostError(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'DatabaseKeyLostError: $message${cause != null ? ' ($cause)' : ''}';
}

/// User- or device-derived secret used to unlock the encrypted database.
class DatabasePassphrase {
  const DatabasePassphrase(this.value);

  /// Plain passphrase value; callers must never log or persist it.
  final String value;
}

/// Retrieves and clears the secret used to unlock the encrypted database.
abstract interface class DatabasePassphraseProvider {
  /// Returns a stable passphrase for this app install.
  Future<DatabasePassphrase> getPassphrase();

  /// Clears the wrapped passphrase and backing keystore key.
  Future<void> clearStoredPassphrase();
}

/// Provides independent Keystore slots for staged database recovery. A new
/// generation is not active until its manifest is atomically published.
abstract interface class GenerationDatabasePassphraseProvider
    implements DatabasePassphraseProvider {
  Future<DatabasePassphrase> createGenerationPassphrase(String generationId);
  Future<DatabasePassphrase> getGenerationPassphrase(String generationId);
  Future<void> deleteGenerationPassphrase(String generationId);
  Future<Set<String>> getGenerationIds();
  Future<String?> getActiveGenerationId();
  Future<Set<String>> getStagingGenerationIds();
  Future<void> activateGeneration(String generationId);
  Future<void> clearAllGenerationPassphrases();
}

/// Android Keystore-backed database passphrase provider.
///
/// The native implementation generates a passphrase once, wraps it with an
/// Android Keystore AES key, and stores only encrypted bytes in app-private
/// storage. StrongBox is requested when the device reports support.
class AndroidKeystoreDatabasePassphraseProvider
    implements GenerationDatabasePassphraseProvider {
  const AndroidKeystoreDatabasePassphraseProvider({
    keystore.AndroidKeystoreDatabasePassphraseProvider? delegate,
  }) : _delegate = delegate ??
            const keystore.AndroidKeystoreDatabasePassphraseProvider();

  final keystore.AndroidKeystoreDatabasePassphraseProvider _delegate;

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    final res = await _delegate.getPassphrase();
    return DatabasePassphrase(res.value);
  }

  @override
  Future<void> clearStoredPassphrase() async {
    await _delegate.clearStoredPassphrase();
  }

  @override
  Future<DatabasePassphrase> createGenerationPassphrase(
    String generationId,
  ) async {
    final result = await _delegate.createGenerationPassphrase(generationId);
    return DatabasePassphrase(result.value);
  }

  @override
  Future<DatabasePassphrase> getGenerationPassphrase(
    String generationId,
  ) async {
    final result = await _delegate.getGenerationPassphrase(generationId);
    return DatabasePassphrase(result.value);
  }

  @override
  Future<void> deleteGenerationPassphrase(String generationId) =>
      _delegate.deleteGenerationPassphrase(generationId);

  @override
  Future<Set<String>> getGenerationIds() => _delegate.getGenerationIds();

  @override
  Future<String?> getActiveGenerationId() => _delegate.getActiveGenerationId();

  @override
  Future<Set<String>> getStagingGenerationIds() =>
      _delegate.getStagingGenerationIds();

  @override
  Future<void> activateGeneration(String generationId) =>
      _delegate.activateGeneration(generationId);

  @override
  Future<void> clearAllGenerationPassphrases() =>
      _delegate.clearAllGenerationPassphrases();

  /// Clears stored passphrase in debug builds for tests.
  @visibleForTesting
  Future<void> debugResetForTests() async {
    await _delegate.debugResetForTests();
  }
}

/// Opens the app database through SQLCipher and fails closed if unavailable.
///
/// The passphrase is escaped before embedding in SQLite PRAGMA syntax.
QueryExecutor openEncryptedDatabase({
  required File file,
  required DatabasePassphrase passphrase,
}) {
  return NativeDatabase.createInBackground(
    file,
    isolateSetup: _prepareSqlCipher,
    setup: (database) {
      if (database.select('PRAGMA cipher_version').isEmpty) {
        throw StateError('SQLCipher not available for this database');
      }

      database.execute(
        "PRAGMA key = '${_escapeSqliteString(passphrase.value)}'",
      );
    },
  );
}

Future<void> _prepareSqlCipher() async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  } else {
    // Desktop hosts (unit-test VM, CI runners, any future desktop build) don't
    // load the bundled Flutter libs, so the default resolver finds plain
    // SQLite with no cipher. Point the sqlite3 loader at a system SQLCipher
    // build when one is present; otherwise leave the default in place so the
    // caller's `PRAGMA cipher_version` guard degrades gracefully.
    final libPath = _findDesktopSqlCipherLib();
    if (libPath != null) {
      final os =
          Platform.isMacOS ? OperatingSystem.macOS : OperatingSystem.linux;
      open.overrideFor(os, () => DynamicLibrary.open(libPath));
    }
  }

  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
}

/// Locates a system SQLCipher shared library on desktop hosts. Honors a
/// `SQLCIPHER_LIB` env override first (used by CI), then falls back to the
/// standard Homebrew (macOS) and apt (Linux) install locations. Returns null
/// when none is found so callers can fail closed on a missing cipher.
String? _findDesktopSqlCipherLib() {
  final override = Platform.environment['SQLCIPHER_LIB'];
  if (override != null && override.isNotEmpty && File(override).existsSync()) {
    return override;
  }

  const candidates = <String>[
    // macOS (Homebrew, Apple Silicon and Intel prefixes).
    '/opt/homebrew/opt/sqlcipher/lib/libsqlcipher.dylib',
    '/usr/local/opt/sqlcipher/lib/libsqlcipher.dylib',
    // Linux (Debian/Ubuntu). The unversioned dev symlink is stable across
    // soname bumps; the versioned names cover a runtime-only install
    // (libsqlcipher1 on noble, libsqlcipher0 on older releases).
    '/usr/lib/x86_64-linux-gnu/libsqlcipher.so',
    '/usr/lib/x86_64-linux-gnu/libsqlcipher.so.1',
    '/usr/lib/x86_64-linux-gnu/libsqlcipher.so.0',
    '/usr/lib/aarch64-linux-gnu/libsqlcipher.so',
    '/usr/lib/aarch64-linux-gnu/libsqlcipher.so.1',
    '/usr/lib/aarch64-linux-gnu/libsqlcipher.so.0',
    '/usr/lib/libsqlcipher.so',
    '/usr/lib/libsqlcipher.so.0',
    // Source build (`make install`) default prefix.
    '/usr/local/lib/libsqlcipher.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

String _escapeSqliteString(String value) {
  return value.replaceAll("'", "''");
}
