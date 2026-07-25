import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/crypto/database_cipher.dart';
import 'database.dart';

const appDatabaseFileName = 'paisatrack.db';

/// Provides the Android Keystore-backed passphrase source for SQLCipher.
///
/// Tests can override this provider or `appDatabaseProvider` directly when a
/// fake or in-memory database is more appropriate than platform channels.
final databasePassphraseProvider = Provider<DatabasePassphraseProvider>((ref) {
  return AndroidKeystoreDatabasePassphraseProvider();
});

/// Resolves the app-private directory that contains the encrypted database.
final databaseDirectoryProvider = FutureProvider<Directory>((ref) async {
  return getApplicationDocumentsDirectory();
});

/// Opens the encrypted application database for app-level consumers.
///
/// The provider owns the database lifetime and closes it when the surrounding
/// `ProviderScope` is disposed. Callers that need deterministic tests should
/// override this provider with an `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final directory = await ref.watch(databaseDirectoryProvider.future);
  final passphraseProvider = ref.watch(databasePassphraseProvider);
  final dbFile = File(p.join(directory.path, appDatabaseFileName));
  final dbExists = dbFile.existsSync();

  DatabasePassphrase passphrase;
  try {
    passphrase = await passphraseProvider.getPassphrase();
  } on Exception catch (e) {
    if (dbExists) {
      throw DatabaseKeyLostError(
        'Database passphrase decryption failed against an existing database file',
        e,
      );
    }
    await passphraseProvider.clearStoredPassphrase();
    passphrase = await passphraseProvider.getPassphrase();
  }

  final database = AppDatabase(
    openEncryptedDatabase(
      file: dbFile,
      passphrase: passphrase,
    ),
  );


  ref.onDispose(() {
    closeAppDatabase(database);
  });

  // T-039 regression fix: the categorizer stamps `category_id` on every parsed
  // transaction and `PRAGMA foreign_keys = ON` enforces the reference, so the
  // bundled defaults MUST exist before any ingest runs. Idempotent
  // (insertOrIgnore) and preserves user-edited rows.
  await database.seedDefaultCategories();

  return database;
});

Future<void> closeAppDatabase(AppDatabase database) async {
  try {
    await database.close();
  } on StateError {
    // Reset flows may close a provider-owned database before Riverpod disposes
    // it. Treat an already-closed database as closed.
  }
}
