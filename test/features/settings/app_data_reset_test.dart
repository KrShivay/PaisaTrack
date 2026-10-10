import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/sms_import_state.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/settings/app_data_reset_service.dart';

class _FakePassphraseProvider implements GenerationDatabasePassphraseProvider {
  String? _secret = 'test_secret';
  int clearGenerationCalls = 0;
  String? activeGeneration;
  final Set<String> stagingGenerations = {};

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    return DatabasePassphrase(_secret ?? 'fresh_secret');
  }

  @override
  Future<void> clearStoredPassphrase() async {
    _secret = null;
  }

  @override
  Future<DatabasePassphrase> createGenerationPassphrase(
    String generationId,
  ) async =>
      DatabasePassphrase('generation:$generationId');

  @override
  Future<DatabasePassphrase> getGenerationPassphrase(
    String generationId,
  ) async =>
      DatabasePassphrase('generation:$generationId');

  @override
  Future<void> deleteGenerationPassphrase(String generationId) async {}

  @override
  Future<Set<String>> getGenerationIds() async => {};

  @override
  Future<String?> getActiveGenerationId() async => activeGeneration;

  @override
  Future<Set<String>> getStagingGenerationIds() async =>
      Set<String>.of(stagingGenerations);

  @override
  Future<void> activateGeneration(String generationId) async {
    activeGeneration = generationId;
  }

  @override
  Future<void> clearAllGenerationPassphrases() async {
    clearGenerationCalls++;
    activeGeneration = null;
    stagingGenerations.clear();
  }
}

class _FakeBackfillMarker implements BackfillMarker {
  @override
  Future<int> completedVersion() async => 0;

  @override
  Future<SmsImportCheckpoint?> checkpoint() async => null;

  @override
  Future<void> saveCheckpoint(SmsImportCheckpoint checkpoint) async {}

  @override
  Future<void> clearCheckpoint() async {}

  @override
  Future<void> markCompleted(int version) async {}

  @override
  Future<void> reset() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'AppDataResetService deleteEverything resets DB and seeds default categories',
    () async {
      late AppDatabase activeDatabase;
      final tempDir = Directory.systemTemp.createTempSync(
        'paisatrack_reset_test',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      var lockHeld = false;
      var databaseOpens = 0;

      final container = ProviderContainer(
        overrides: [
          databaseDirectoryProvider.overrideWith((ref) async => tempDir),
          databasePassphraseProvider.overrideWithValue(
            _FakePassphraseProvider(),
          ),
          backfillMarkerProvider.overrideWithValue(_FakeBackfillMarker()),
          appDatabaseProvider.overrideWith((ref) async {
            if (databaseOpens > 0) {
              expect(
                lockHeld,
                isTrue,
                reason: 'Reset must hold the worker lock through database open',
              );
            }
            databaseOpens++;
            activeDatabase = AppDatabase(NativeDatabase.memory());
            return activeDatabase;
          }),
          appDataResetServiceProvider.overrideWith(
            (ref) => AppDataResetService(
              ref,
              lockRunner: <T>(directory, action) async {
                lockHeld = true;
                try {
                  return await action();
                } finally {
                  lockHeld = false;
                }
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Initial database seed
      final dbBefore = await container.read(appDatabaseProvider.future);
      await dbBefore.seedDefaultCategories();

      final resetService = container.read(appDataResetServiceProvider);
      final result = await resetService.deleteEverything();

      expect(result.categoryCount, greaterThan(0));
      expect(databaseOpens, 2);
      expect(lockHeld, isFalse);

      final freshDb = await container.read(appDatabaseProvider.future);
      final categories = await freshDb.select(freshDb.categories).get();
      expect(categories.length, equals(result.categoryCount));
    },
  );

  test(
    'Settings reset removes every generation family and recovery archive',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'paisatrack_reset_generations',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      const id = 'd92f2cb4-c682-4e38-95e4-7c9a88e43f1a';
      final passphrases = _FakePassphraseProvider()..activeGeneration = id;
      passphrases.stagingGenerations.add(
        '8c4bc60d-9c99-40c8-94c1-b3b176934fa8',
      );
      final generationBase = File(
        '${tempDir.path}/${const AppDatabaseGeneration(id).fileName}',
      );
      final legacyBase = File('${tempDir.path}/$appDatabaseFileName');
      final archivedDb = File(
        '${tempDir.path}/database-recovery-archive/$id/${const AppDatabaseGeneration(id).fileName}',
      );
      for (final file in [
        generationBase,
        File('${generationBase.path}-wal'),
        legacyBase,
        File('${legacyBase.path}-journal'),
        File(
          '${tempDir.path}/paisatrack.8c4bc60d-9c99-40c8-94c1-b3b176934fa8.db-shm',
        ),
        archivedDb,
      ]) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1, 2, 3]);
      }

      final container = ProviderContainer(
        overrides: [
          databaseDirectoryProvider.overrideWith((ref) async => tempDir),
          databasePassphraseProvider.overrideWithValue(passphrases),
          backfillMarkerProvider.overrideWithValue(_FakeBackfillMarker()),
          appDatabaseProvider.overrideWith(
            (ref) async => AppDatabase(NativeDatabase.memory()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(appDataResetServiceProvider).deleteEverything();

      expect(result.deletedFiles, 6);
      expect(await generationBase.exists(), isFalse);
      expect(await File('${generationBase.path}-wal').exists(), isFalse);
      expect(await legacyBase.exists(), isFalse);
      expect(await File('${legacyBase.path}-journal').exists(), isFalse);
      expect(await archivedDb.exists(), isFalse);
      expect(
        await File(
          '${tempDir.path}/paisatrack.8c4bc60d-9c99-40c8-94c1-b3b176934fa8.db-shm',
        ).exists(),
        isFalse,
      );
      expect(
        await Directory('${tempDir.path}/database-recovery-archive').exists(),
        isFalse,
      );
      expect(passphrases.clearGenerationCalls, 1);
      expect(passphrases.activeGeneration, isNull);
      expect(passphrases.stagingGenerations, isEmpty);
    },
  );
}
