import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/crypto/database_cipher.dart';
import 'database.dart';

const appDatabaseFileName = 'paisatrack.db';

/// Namespaced encrypted database generations allow recovery to switch the
/// active key/file pointer without replacing the existing encrypted bytes.
class AppDatabaseGeneration {
  const AppDatabaseGeneration(this.id);

  final String id;

  String get fileName => 'paisatrack.$id.db';

  static bool isValidId(String id) => RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id);
}

class ActiveDatabaseConfig {
  const ActiveDatabaseConfig({
    required this.file,
    required this.passphrase,
    required this.generationId,
  });

  final File file;
  final DatabasePassphrase passphrase;
  final String? generationId;
}

/// Resolve the current database target for foreground and worker entry points.
/// Only first-run legacy startup may clear a wrapped key, and only when the
/// corresponding legacy database file is absent.
Future<ActiveDatabaseConfig> resolveActiveDatabaseConfig({
  required Directory directory,
  required DatabasePassphraseProvider passphrases,
  bool initializeMissingLegacyDatabase = false,
}) async {
  final generationProvider =
      passphrases is GenerationDatabasePassphraseProvider ? passphrases : null;
  String? generationId;
  if (generationProvider != null) {
    try {
      generationId = await generationProvider.getActiveGenerationId();
    } on Object catch (error) {
      throw DatabaseKeyLostError(
        'Database generation state is unavailable',
        error,
      );
    }
  }

  if (generationId != null && !AppDatabaseGeneration.isValidId(generationId)) {
    throw const DatabaseKeyLostError('Database generation state is invalid');
  }
  final generationFileIds = await _generationDatabaseIds(directory);
  if (generationId == null && generationFileIds.isNotEmpty) {
    if (generationProvider == null) {
      throw const DatabaseKeyLostError(
        'Database generation state is missing while generation files exist',
      );
    }
    final stagingIds = await _readStagingGenerationIds(generationProvider);
    if (!generationFileIds.every(stagingIds.contains)) {
      throw const DatabaseKeyLostError(
        'Database generation state is missing while non-staging generation files exist',
      );
    }
  } else if (generationId != null && generationProvider != null) {
    final stagingIds = await _readStagingGenerationIds(generationProvider);
    if (stagingIds.contains(generationId)) {
      throw const DatabaseKeyLostError(
        'Active database generation is still marked as staging',
      );
    }
  }
  final file = File(
    p.join(
      directory.path,
      generationId == null
          ? appDatabaseFileName
          : AppDatabaseGeneration(generationId).fileName,
    ),
  );
  final fileExists = await _databaseFamilyExists(file);
  if (generationId != null && !fileExists) {
    throw const DatabaseKeyLostError(
      'Active database generation file is missing',
    );
  }

  try {
    final passphrase = generationId == null
        ? await passphrases.getPassphrase()
        : await generationProvider!.getGenerationPassphrase(generationId);
    return ActiveDatabaseConfig(
      file: file,
      passphrase: passphrase,
      generationId: generationId,
    );
  } on Object catch (error) {
    if (generationId != null ||
        fileExists ||
        !initializeMissingLegacyDatabase) {
      throw DatabaseKeyLostError(
        'Database passphrase is unavailable for the active database',
        error,
      );
    }
    try {
      await passphrases.clearStoredPassphrase();
      final passphrase = await passphrases.getPassphrase();
      return ActiveDatabaseConfig(
        file: file,
        passphrase: passphrase,
        generationId: null,
      );
    } on Object catch (retryError) {
      throw DatabaseKeyLostError(
        'Could not initialize the first local database key',
        retryError,
      );
    }
  }
}

Future<bool> _databaseFamilyExists(File baseFile) async {
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    if (await File('${baseFile.path}$suffix').exists()) return true;
  }
  return false;
}

Future<Set<String>> _generationDatabaseIds(Directory directory) async {
  final ids = <String>{};
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    final match =
        RegExp(r'^paisatrack\.([0-9a-f-]{36})\.db(?:-(?:wal|shm|journal))?$')
            .firstMatch(name);
    if (match != null && AppDatabaseGeneration.isValidId(match.group(1)!)) {
      ids.add(match.group(1)!);
    }
  }
  return ids;
}

Future<Set<String>> _readStagingGenerationIds(
  GenerationDatabasePassphraseProvider provider,
) async {
  try {
    final ids = await provider.getStagingGenerationIds();
    if (ids.any((id) => !AppDatabaseGeneration.isValidId(id))) {
      throw const DatabaseKeyLostError('Staging generation state is invalid');
    }
    return ids;
  } on DatabaseKeyLostError {
    rethrow;
  } on Object catch (error) {
    throw DatabaseKeyLostError(
      'Staging generation state is unavailable',
      error,
    );
  }
}

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
  final config = await resolveActiveDatabaseConfig(
    directory: directory,
    passphrases: passphraseProvider,
    initializeMissingLegacyDatabase: true,
  );

  final database = AppDatabase(
    openEncryptedDatabase(file: config.file, passphrase: config.passphrase),
  );

  ref.onDispose(() {
    closeAppDatabase(database);
  });

  try {
    // T-039 regression fix: the categorizer stamps `category_id` on every parsed
    // transaction and `PRAGMA foreign_keys = ON` enforces the reference, so the
    // bundled defaults MUST exist before any ingest runs. Idempotent
    // (insertOrIgnore) and preserves user-edited rows.
    await database.seedDefaultCategories();
    await database.seedDefaultFeatureFlags();
  } on Object catch (e) {
    await closeAppDatabase(database);
    if (await config.file.exists()) {
      throw DatabaseKeyLostError(
        'Database passphrase decryption or initialization failed against an existing database file',
        e,
      );
    }
    rethrow;
  }

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
