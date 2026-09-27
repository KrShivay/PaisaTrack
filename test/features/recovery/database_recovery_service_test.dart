import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/core/platform/system_document_gateway.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/backup/encrypted_backup_service.dart';
import 'package:paisatrack/features/recovery/database_recovery_service.dart';

class _FakePassphrases implements GenerationDatabasePassphraseProvider {
  final Map<String, DatabasePassphrase> keys = {};
  final Set<String> stagingGenerations = {};
  String? activeGeneration;
  int legacyClearCalls = 0;
  bool failActivationBeforeCommit = false;
  bool failActivationAfterCommit = false;

  @override
  Future<DatabasePassphrase> getPassphrase() async =>
      const DatabasePassphrase('legacy-key');

  @override
  Future<void> clearStoredPassphrase() async {
    legacyClearCalls++;
  }

  @override
  Future<DatabasePassphrase> createGenerationPassphrase(
    String generationId,
  ) async {
    final key = keys.putIfAbsent(
      generationId,
      () => DatabasePassphrase('new-key:$generationId'),
    );
    stagingGenerations.add(generationId);
    return key;
  }

  @override
  Future<DatabasePassphrase> getGenerationPassphrase(
    String generationId,
  ) async {
    final key = keys[generationId];
    if (key == null) throw StateError('generation key missing');
    return key;
  }

  @override
  Future<void> deleteGenerationPassphrase(String generationId) async {
    if (activeGeneration != generationId) keys.remove(generationId);
    stagingGenerations.remove(generationId);
  }

  @override
  Future<Set<String>> getGenerationIds() async => Set.of(keys.keys);

  @override
  Future<String?> getActiveGenerationId() async => activeGeneration;

  @override
  Future<Set<String>> getStagingGenerationIds() async =>
      Set<String>.of(stagingGenerations);

  @override
  Future<void> activateGeneration(String generationId) async {
    if (failActivationBeforeCommit) throw StateError('commit failed');
    await getGenerationPassphrase(generationId);
    activeGeneration = generationId;
    stagingGenerations.remove(generationId);
    if (failActivationAfterCommit) throw StateError('reply lost after commit');
  }

  @override
  Future<void> clearAllGenerationPassphrases() async {
    keys.clear();
    stagingGenerations.clear();
    activeGeneration = null;
  }
}

class _MemoryDocumentGateway extends SystemDocumentGateway {
  _MemoryDocumentGateway() : super();

  final _written = <int>[];
  var _readOffset = 0;
  bool cancelOpen = false;

  void setSource(List<int> bytes) {
    _written
      ..clear()
      ..addAll(bytes);
  }

  @override
  Future<bool> finishDocument({required String sessionId}) async => true;

  @override
  Future<String?> beginSaveDocument({
    required String suggestedName,
    required String mimeType,
  }) async {
    _written.clear();
    return 'save';
  }

  @override
  Future<bool> writeDocumentChunk({
    required String sessionId,
    required Uint8List bytes,
  }) async {
    _written.addAll(bytes);
    return true;
  }

  @override
  Future<void> cancelDocument({required String sessionId}) async {}

  @override
  Future<String?> beginOpenDocument({required String mimeType}) async {
    if (cancelOpen) return null;
    _readOffset = 0;
    return 'open';
  }

  @override
  Future<Uint8List?> readDocumentChunk({
    required String sessionId,
    int maxBytes = maxDocumentChunkBytes,
  }) async {
    if (_readOffset >= _written.length) return null;
    final end = min(_readOffset + maxBytes, _written.length);
    final chunk = Uint8List.fromList(_written.sublist(_readOffset, end));
    _readOffset = end;
    return chunk;
  }

  @override
  Future<void> closeDocument({required String sessionId}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;
  late _FakePassphrases passphrases;
  late _MemoryDocumentGateway documents;
  late AppDatabase sourceDatabase;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('paisatrack_recovery_test');
    passphrases = _FakePassphrases();
    documents = _MemoryDocumentGateway();
    sourceDatabase = AppDatabase(NativeDatabase.memory());
    await sourceDatabase.seedDefaultCategories();
    await sourceDatabase.into(sourceDatabase.paymentSources).insert(
          PaymentSourcesCompanion.insert(
            id: 'recovery_source',
            kind: 'card',
            maskedIdentifier: 'xx4242',
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await EncryptedBackupService(database: sourceDatabase).exportToDocument(
      gateway: documents,
      suggestedName: 'backup.ptrack',
      mimeType: 'application/octet-stream',
      passphrase: 'correct backup passphrase',
    );
  });

  tearDown(() async {
    await sourceDatabase.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  DatabaseRecoveryService service() => DatabaseRecoveryService(
        directory: directory,
        passphrases: passphrases,
        documents: documents,
        databaseFactory: (file, _) {
          // Keep a file marker so this test exercises generation-family and
          // archival behavior while using an in-memory Drift database.
          file.writeAsBytesSync([0x53, 0x54, 0x41, 0x47, 0x45]);
          return AppDatabase(NativeDatabase.memory());
        },
      );

  test('imports into a new generation, archives old bytes, and activates last',
      () async {
    final oldFile = File('${directory.path}/$appDatabaseFileName');
    final oldWal = File('${oldFile.path}-wal');
    await oldFile.writeAsBytes([0, 1, 2, 3, 4]);
    await oldWal.writeAsBytes([5, 6, 7]);
    final oldFileBytes = await oldFile.readAsBytes();
    final oldWalBytes = await oldWal.readAsBytes();

    final result = await service().restoreFromDocument(
      passphrase: 'correct backup passphrase',
    );

    expect(result, isNotNull);
    expect(result!.paymentSourceCount, 1);
    expect(result.preservedFiles, 2);
    expect(passphrases.activeGeneration, isNotNull);
    expect(
      AppDatabaseGeneration.isValidId(passphrases.activeGeneration!),
      isTrue,
    );
    final generationFile = File(
      '${directory.path}/${AppDatabaseGeneration(passphrases.activeGeneration!).fileName}',
    );
    expect(await generationFile.exists(), isTrue);
    expect(await oldFile.readAsBytes(), oldFileBytes);
    expect(await oldWal.readAsBytes(), oldWalBytes);
    expect(passphrases.legacyClearCalls, 0);
    final archived = Directory(
      '${directory.path}/database-recovery-archive/${passphrases.activeGeneration}',
    );
    expect(
      await File('${archived.path}/$appDatabaseFileName').readAsBytes(),
      oldFileBytes,
    );
    final reopened = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
    );
    expect(reopened.generationId, passphrases.activeGeneration);
    expect(reopened.file.path, generationFile.path);
  });

  test('wrong passphrase leaves legacy bytes and key selector unchanged',
      () async {
    final oldFile = File('${directory.path}/$appDatabaseFileName');
    await oldFile.writeAsBytes([9, 8, 7, 6]);

    await expectLater(
      service().restoreFromDocument(passphrase: 'wrong backup passphrase'),
      throwsA(isA<EncryptedBackupException>()),
    );

    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.keys, isEmpty);
    expect(passphrases.legacyClearCalls, 0);
    expect(await oldFile.readAsBytes(), [9, 8, 7, 6]);
    expect(
      (await directory.list().toList())
          .where((entity) => entity is File && entity.path != oldFile.path),
      isEmpty,
    );
  });

  test('picker cancel removes only unselected staging files and key', () async {
    documents.cancelOpen = true;
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([9, 8, 7]);

    final result = await service().restoreFromDocument(
      passphrase: 'correct backup passphrase',
    );

    expect(result, isNull);
    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.keys, isEmpty);
    expect(passphrases.stagingGenerations, isEmpty);
    expect(await legacyFile.readAsBytes(), [9, 8, 7]);
  });

  test('truncated archive removes only unselected staging files and key',
      () async {
    documents.setSource([0x50, 0x54, 0x52]);
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([3, 4, 5]);

    await expectLater(
      service().restoreFromDocument(passphrase: 'correct backup passphrase'),
      throwsA(isA<EncryptedBackupException>()),
    );

    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.keys, isEmpty);
    expect(passphrases.stagingGenerations, isEmpty);
    expect(await legacyFile.readAsBytes(), [3, 4, 5]);
  });

  test('failed staging cleanup retains its key and marker for legacy startup',
      () async {
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([1, 5, 9]);
    final recovery = DatabaseRecoveryService(
      directory: directory,
      passphrases: passphrases,
      documents: documents,
      databaseFactory: (file, _) {
        file.writeAsBytesSync([0x53, 0x54, 0x41, 0x47, 0x45]);
        return AppDatabase(NativeDatabase.memory());
      },
      generationCleanup: (_) async =>
          throw const FileSystemException('simulated delete failure'),
    );

    await expectLater(
      recovery.restoreFromDocument(passphrase: 'wrong backup passphrase'),
      throwsA(isA<EncryptedBackupException>()),
    );

    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.stagingGenerations, hasLength(1));
    expect(passphrases.keys, hasLength(1));
    final stagedId = passphrases.stagingGenerations.single;
    final stagedFile = File(
      '${directory.path}/${AppDatabaseGeneration(stagedId).fileName}',
    );
    expect(await stagedFile.exists(), isTrue);
    expect(await legacyFile.readAsBytes(), [1, 5, 9]);

    final selected = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
      initializeMissingLegacyDatabase: true,
    );
    expect(selected.file.path, legacyFile.path);
    expect(selected.generationId, isNull);
  });

  test('archive copy failure removes partial archive and staging state',
      () async {
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([7, 6, 5, 4]);
    final recovery = DatabaseRecoveryService(
      directory: directory,
      passphrases: passphrases,
      documents: documents,
      databaseFactory: (file, _) {
        file.writeAsBytesSync([0x53, 0x54, 0x41, 0x47, 0x45]);
        return AppDatabase(NativeDatabase.memory());
      },
      archiveCopy: (source, targetPath) async =>
          throw const FileSystemException('simulated storage exhaustion'),
    );

    await expectLater(
      recovery.restoreFromDocument(passphrase: 'correct backup passphrase'),
      throwsA(isA<FileSystemException>()),
    );

    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.keys, isEmpty);
    expect(passphrases.stagingGenerations, isEmpty);
    expect(await legacyFile.readAsBytes(), [7, 6, 5, 4]);
    expect(
      await Directory('${directory.path}/database-recovery-archive').exists(),
      isFalse,
    );
  });

  test('activation failure before commit leaves legacy selector usable',
      () async {
    passphrases.failActivationBeforeCommit = true;
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([6, 5, 4, 3]);

    await expectLater(
      service().restoreFromDocument(passphrase: 'correct backup passphrase'),
      throwsA(isA<StateError>()),
    );

    expect(passphrases.activeGeneration, isNull);
    expect(passphrases.stagingGenerations, hasLength(1));
    expect(passphrases.keys, hasLength(1));
    expect(await legacyFile.readAsBytes(), [6, 5, 4, 3]);
    final reopened = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
      initializeMissingLegacyDatabase: true,
    );
    expect(reopened.generationId, isNull);
    expect(reopened.file.path, legacyFile.path);
  });

  test('activation response failure after commit resolves to new generation',
      () async {
    passphrases.failActivationAfterCommit = true;
    final legacyFile = File('${directory.path}/$appDatabaseFileName');
    await legacyFile.writeAsBytes([2, 4, 6, 8]);

    final result = await service().restoreFromDocument(
      passphrase: 'correct backup passphrase',
    );

    expect(result, isNotNull);
    expect(passphrases.activeGeneration, isNotNull);
    expect(passphrases.stagingGenerations, isEmpty);
    expect(await legacyFile.readAsBytes(), [2, 4, 6, 8]);
    final reopened = await resolveActiveDatabaseConfig(
      directory: directory,
      passphrases: passphrases,
    );
    expect(reopened.generationId, passphrases.activeGeneration);
  });
}
