import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../capture/sms_import_state.dart';
import '../../core/crypto/database_cipher.dart';
import '../../data/db/database_file_lock.dart';
import '../../data/db/database_provider.dart';
import 'app_settings.dart';

class AppDataResetResult {
  const AppDataResetResult({
    required this.deletedFiles,
    required this.categoryCount,
  });

  final int deletedFiles;
  final int categoryCount;
}

typedef DatabaseFileLockRunner = Future<T> Function<T>(
  Directory directory,
  Future<T> Function() action,
);

class AppDataResetService {
  const AppDataResetService(this._ref, {DatabaseFileLockRunner? lockRunner})
      : _lockRunner = lockRunner ?? withDatabaseFileLock;

  final Ref _ref;
  final DatabaseFileLockRunner _lockRunner;

  Future<AppDataResetResult> deleteEverything() async {
    final directory = await _ref.read(databaseDirectoryProvider.future);
    final passphrases = _ref.read(databasePassphraseProvider);
    return _lockRunner(directory, () async {
      // Wait for the nightly writer and hold its lock until its DB files and
      // keys are erased. Awaiting the provider's open matters here: reading
      // only AsyncValue.valueOrNull can race a pending open during deletion.
      try {
        final existingDatabase = await _ref.read(appDatabaseProvider.future);
        await closeAppDatabase(existingDatabase);
      } on Object {
        // Reset also handles an unreadable database or failed key lookup.
      }

      final removed = await _deleteDatabaseFiles(directory);

      try {
        await const MethodChannel(
          'com.paisatrack/reset',
        ).invokeMethod<void>('clearAllNativeState');
      } on MissingPluginException {
        // Ignored when host channel is not registered (e.g. desktop unit tests)
      } catch (_) {
        // Ignore native reset failures during local erasure
      }

      if (passphrases is GenerationDatabasePassphraseProvider) {
        await passphrases.clearAllGenerationPassphrases();
      }
      await passphrases.clearStoredPassphrase();
      await _ref.read(appSettingsControllerProvider.notifier).resetToDefaults();
      await _ref.read(backfillMarkerProvider).reset();

      _ref.invalidate(appDatabaseProvider);
      final freshDatabase = await _ref.read(appDatabaseProvider.future);
      await freshDatabase.seedDefaultCategories();
      final categoryCount = await freshDatabase
          .select(freshDatabase.categories)
          .get()
          .then((rows) => rows.length);

      return AppDataResetResult(
        deletedFiles: removed,
        categoryCount: categoryCount,
      );
    });
  }

  Future<int> _deleteDatabaseFiles(Directory directory) async {
    var deleted = 0;
    final databaseBases = <String>{appDatabaseFileName};
    await for (final entity in directory.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final match = RegExp(
        r'^paisatrack\.([0-9a-f-]{36})\.db(?:-(?:wal|shm|journal))?$',
      ).firstMatch(name);
      if (match != null && AppDatabaseGeneration.isValidId(match.group(1)!)) {
        databaseBases.add(AppDatabaseGeneration(match.group(1)!).fileName);
      }
    }

    for (final base in databaseBases) {
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final file = File(p.join(directory.path, '$base$suffix'));
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      }
    }

    final archive = Directory(
      p.join(directory.path, 'database-recovery-archive'),
    );
    if (await archive.exists()) {
      await for (final entry in archive.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) deleted++;
      }
      await archive.delete(recursive: true);
    }
    return deleted;
  }
}

final appDataResetServiceProvider = Provider<AppDataResetService>((ref) {
  return AppDataResetService(ref);
});
