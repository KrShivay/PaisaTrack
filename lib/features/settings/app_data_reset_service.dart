import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../capture/sms_import_state.dart';
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

class AppDataResetService {
  const AppDataResetService(this._ref);

  final Ref _ref;

  Future<AppDataResetResult> deleteEverything() async {
    // Await the provider's current open before invalidating it. Reading only
    // AsyncValue.valueOrNull starts an open but can return null while that open
    // is pending, allowing the replacement database to overlap with it.
    try {
      final existingDatabase = await _ref.read(appDatabaseProvider.future);
      await closeAppDatabase(existingDatabase);
    } on Object {
      // Reset is also the recovery path for an unreadable/corrupt database or
      // a failed passphrase lookup. File/key deletion must still be attempted.
    }

    final directory = await _ref.read(databaseDirectoryProvider.future);
    final deletedFiles = await _deleteDatabaseFiles(directory);

    try {
      await const MethodChannel('com.paisatrack/reset')
          .invokeMethod<void>('clearAllNativeState');
    } on MissingPluginException {
      // Ignored when host channel is not registered (e.g. desktop unit tests)
    } catch (_) {
      // Ignore native reset failures during local erasure
    }

    await _ref.read(databasePassphraseProvider).clearStoredPassphrase();
    await _ref.read(appSettingsControllerProvider.notifier).resetToDefaults();
    await _ref.read(backfillMarkerProvider).reset();

    _ref.invalidate(appDatabaseProvider);
    final freshDatabase = await _ref.read(appDatabaseProvider.future);
    await freshDatabase.seedDefaultCategories();
    final categoryCount =
        await freshDatabase.select(freshDatabase.categories).get().then(
              (rows) => rows.length,
            );

    return AppDataResetResult(
      deletedFiles: deletedFiles,
      categoryCount: categoryCount,
    );
  }

  Future<int> _deleteDatabaseFiles(Directory directory) async {
    var deleted = 0;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File(p.join(directory.path, '$appDatabaseFileName$suffix'));
      if (await file.exists()) {
        await file.delete();
        deleted++;
      }
    }
    return deleted;
  }
}

final appDataResetServiceProvider = Provider<AppDataResetService>((ref) {
  return AppDataResetService(ref);
});
