import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database_provider.dart';

class _FakePassphrases implements GenerationDatabasePassphraseProvider {
  String? activeGeneration;
  final Map<String, DatabasePassphrase> generations = {};
  final Set<String> stagingGenerations = {};
  DatabasePassphrase? legacyPassphrase = const DatabasePassphrase('legacy');
  int clearLegacyCalls = 0;

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    final passphrase = legacyPassphrase;
    if (passphrase == null) throw StateError('legacy key unavailable');
    return passphrase;
  }

  @override
  Future<void> clearStoredPassphrase() async {
    clearLegacyCalls++;
    legacyPassphrase = null;
  }

  @override
  Future<DatabasePassphrase> createGenerationPassphrase(
    String generationId,
  ) async {
    final key = generations.putIfAbsent(
      generationId,
      () => DatabasePassphrase('generation:$generationId'),
    );
    stagingGenerations.add(generationId);
    return key;
  }

  @override
  Future<DatabasePassphrase> getGenerationPassphrase(
    String generationId,
  ) async {
    final passphrase = generations[generationId];
    if (passphrase == null) throw StateError('generation key unavailable');
    return passphrase;
  }

  @override
  Future<String?> getActiveGenerationId() async => activeGeneration;

  @override
  Future<Set<String>> getStagingGenerationIds() async =>
      Set<String>.of(stagingGenerations);

  @override
  Future<void> activateGeneration(String generationId) async {
    activeGeneration = generationId;
    stagingGenerations.remove(generationId);
  }

  @override
  Future<void> deleteGenerationPassphrase(String generationId) async {
    generations.remove(generationId);
    stagingGenerations.remove(generationId);
  }

  @override
  Future<Set<String>> getGenerationIds() async => Set.of(generations.keys);

  @override
  Future<void> clearAllGenerationPassphrases() async {
    generations.clear();
    stagingGenerations.clear();
    activeGeneration = null;
  }
}

void main() {
  late Directory directory;
  late _FakePassphrases passphrases;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'paisatrack_generation_test',
    );
    passphrases = _FakePassphrases();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('resolves the active generation file and its independent key', () async {
    const id = 'd92f2cb4-c682-4e38-95e4-7c9a88e43f1a';
    final key = await passphrases.createGenerationPassphrase(id);
    await passphrases.activateGeneration(id);
    final file = File(
      '${directory.path}/${const AppDatabaseGeneration(id).fileName}',
    );
    await file.writeAsBytes([1, 2, 3]);

    final resolved = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
      initializeMissingLegacyDatabase: true,
    );

    expect(resolved.file.path, file.path);
    expect(resolved.passphrase.value, key.value);
    expect(resolved.generationId, id);
    expect(passphrases.clearLegacyCalls, 0);
  });

  test('fails closed when active generation file is missing', () async {
    passphrases.activeGeneration = 'd92f2cb4-c682-4e38-95e4-7c9a88e43f1a';

    await expectLater(
      resolveActiveDatabaseConfig(
        directory: directory,
        passphrases: passphrases,
        initializeMissingLegacyDatabase: true,
      ),
      throwsA(isA<DatabaseKeyLostError>()),
    );
    expect(passphrases.clearLegacyCalls, 0);
  });

  test('fails closed on invalid active generation metadata', () async {
    passphrases.activeGeneration = '../paisatrack.db';

    await expectLater(
      resolveActiveDatabaseConfig(
        directory: directory,
        passphrases: passphrases,
        initializeMissingLegacyDatabase: true,
      ),
      throwsA(isA<DatabaseKeyLostError>()),
    );
    expect(passphrases.clearLegacyCalls, 0);
  });

  test(
      'fails closed when generation files exist but the active pointer is absent',
      () async {
    final orphan = File(
      '${directory.path}/paisatrack.d92f2cb4-c682-4e38-95e4-7c9a88e43f1a.db-wal',
    );
    await orphan.writeAsBytes([1, 2, 3]);

    await expectLater(
      resolveActiveDatabaseConfig(
        directory: directory,
        passphrases: passphrases,
        initializeMissingLegacyDatabase: true,
      ),
      throwsA(isA<DatabaseKeyLostError>()),
    );
    expect(passphrases.clearLegacyCalls, 0);
  });

  test('keeps the legacy selector after an interrupted staged generation',
      () async {
    const id = 'd92f2cb4-c682-4e38-95e4-7c9a88e43f1a';
    await passphrases.createGenerationPassphrase(id);
    final stagedFile = File(
      '${directory.path}/${const AppDatabaseGeneration(id).fileName}',
    );
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await stagedFile.writeAsBytes([1, 2, 3]);
    await legacyFile.writeAsBytes([4, 5, 6]);

    final resolved = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
      initializeMissingLegacyDatabase: true,
    );

    expect(resolved.file.path, legacyFile.path);
    expect(resolved.generationId, isNull);
    expect(passphrases.clearLegacyCalls, 0);
    expect(await stagedFile.exists(), isTrue);
  });

  test(
    'does not erase a legacy key when an existing database cannot unlock',
    () async {
      final legacyFile = File('${directory.path}/$appDatabaseFileName');
      await legacyFile.writeAsBytes([0x53, 0x51, 0x4c]);
      passphrases.legacyPassphrase = null;

      await expectLater(
        resolveActiveDatabaseConfig(
          directory: directory,
          passphrases: passphrases,
          initializeMissingLegacyDatabase: true,
        ),
        throwsA(isA<DatabaseKeyLostError>()),
      );
      expect(passphrases.clearLegacyCalls, 0);
    },
  );

  test('does not erase the legacy key when only a WAL sidecar remains',
      () async {
    final legacyWal = File('${directory.path}/$appDatabaseFileName-wal');
    await legacyWal.writeAsBytes([0x57, 0x41, 0x4c]);
    passphrases.legacyPassphrase = null;

    await expectLater(
      resolveActiveDatabaseConfig(
        directory: directory,
        passphrases: passphrases,
        initializeMissingLegacyDatabase: true,
      ),
      throwsA(isA<DatabaseKeyLostError>()),
    );

    expect(passphrases.clearLegacyCalls, 0);
    expect(await legacyWal.readAsBytes(), [0x57, 0x41, 0x4c]);
  });
}
