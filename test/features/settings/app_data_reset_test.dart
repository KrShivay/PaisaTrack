import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/sms_import_state.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/settings/app_data_reset_service.dart';

class _FakePassphraseProvider implements DatabasePassphraseProvider {
  String? _secret = 'test_secret';

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    return DatabasePassphrase(_secret ?? 'fresh_secret');
  }

  @override
  Future<void> clearStoredPassphrase() async {
    _secret = null;
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
  Future<void> markCompleted(int version) async {}

  @override
  Future<void> reset() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppDataResetService deleteEverything resets DB and seeds default categories', () async {
    late AppDatabase activeDatabase;
    final tempDir = Directory.systemTemp.createTempSync('paisatrack_reset_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        databaseDirectoryProvider.overrideWith((ref) async => tempDir),
        databasePassphraseProvider
            .overrideWithValue(_FakePassphraseProvider()),
        backfillMarkerProvider.overrideWithValue(_FakeBackfillMarker()),
        appDatabaseProvider.overrideWith((ref) async {
          activeDatabase = AppDatabase(NativeDatabase.memory());
          return activeDatabase;
        }),
      ],
    );
    addTearDown(container.dispose);

    // Initial database seed
    final dbBefore = await container.read(appDatabaseProvider.future);
    await dbBefore.seedDefaultCategories();

    final resetService = container.read(appDataResetServiceProvider);
    final result = await resetService.deleteEverything();

    expect(result.categoryCount, greaterThan(0));

    final freshDb = await container.read(appDatabaseProvider.future);
    final categories = await freshDb.select(freshDb.categories).get();
    expect(categories.length, equals(result.categoryCount));
  });
}
