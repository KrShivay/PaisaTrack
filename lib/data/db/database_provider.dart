import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/crypto/database_cipher.dart';
import 'database.dart';

const _databaseFileName = 'paisatrack.db';

/// Provides the Android Keystore-backed passphrase source for SQLCipher.
///
/// Tests can override this provider or `appDatabaseProvider` directly when a
/// fake or in-memory database is more appropriate than platform channels.
final databasePassphraseProvider = Provider<DatabasePassphraseProvider>((ref) {
  return const AndroidKeystoreDatabasePassphraseProvider();
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
  final passphrase = await passphraseProvider.getPassphrase();
  final database = AppDatabase(
    openEncryptedDatabase(
      file: File(p.join(directory.path, _databaseFileName)),
      passphrase: passphrase,
    ),
  );

  ref.onDispose(database.close);

  return database;
});
