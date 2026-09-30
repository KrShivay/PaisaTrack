import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/core/platform/system_document_gateway.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/backup/encrypted_backup_service.dart';
import 'package:paisatrack/features/recovery/database_recovery_service.dart';
import 'package:path_provider/path_provider.dart';

class _MemoryDocumentGateway extends SystemDocumentGateway {
  _MemoryDocumentGateway() : super();

  final _bytes = <int>[];
  var _offset = 0;

  @override
  Future<bool> finishDocument({required String sessionId}) async => true;

  @override
  Future<String?> beginSaveDocument({
    required String suggestedName,
    required String mimeType,
  }) async {
    _bytes.clear();
    return 'save';
  }

  @override
  Future<bool> writeDocumentChunk({
    required String sessionId,
    required Uint8List bytes,
  }) async {
    _bytes.addAll(bytes);
    return true;
  }

  @override
  Future<void> cancelDocument({required String sessionId}) async {}

  @override
  Future<String?> beginOpenDocument({required String mimeType}) async {
    _offset = 0;
    return 'open';
  }

  @override
  Future<Uint8List?> readDocumentChunk({
    required String sessionId,
    int maxBytes = maxDocumentChunkBytes,
  }) async {
    if (_offset >= _bytes.length) return null;
    final end = min(_offset + maxBytes, _bytes.length);
    final chunk = Uint8List.fromList(_bytes.sublist(_offset, end));
    _offset = end;
    return chunk;
  }

  @override
  Future<void> closeDocument({required String sessionId}) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Keystore slot restores a synthetic backup into SQLCipher', (
    tester,
  ) async {
    await verifyRecoveryQaIdentity();
    const generationKeys = AndroidKeystoreDatabasePassphraseProvider();
    final initialGenerationIds = await generationKeys.getGenerationIds();
    expect(
      initialGenerationIds,
      isEmpty,
      reason: 'The emulator rehearsal requires an isolated generation registry',
    );
    expect(await generationKeys.getActiveGenerationId(), isNull);
    expect(await generationKeys.getStagingGenerationIds(), isEmpty);
    final document = _MemoryDocumentGateway();
    final testDirectory = Directory(
      '${(await getTemporaryDirectory()).path}/recovery-device-${DateTime.now().microsecondsSinceEpoch}',
    );
    await testDirectory.create(recursive: true);
    final backupDatabase = AppDatabase(
      openEncryptedDatabase(
        file: File('${testDirectory.path}/synthetic-source.db'),
        passphrase: const DatabasePassphrase(
          'device synthetic database passphrase',
        ),
      ),
    );
    final oldDatabase = File('${testDirectory.path}/paisatrack.db');
    await oldDatabase
        .writeAsBytes([0x50, 0x52, 0x45, 0x56, 0x49, 0x4f, 0x55, 0x53]);
    String? generationId;
    AppDatabase? restored;

    try {
      await backupDatabase.seedDefaultCategories();
      await backupDatabase.into(backupDatabase.paymentSources).insert(
            PaymentSourcesCompanion.insert(
              id: 'device_recovery_source',
              kind: 'card',
              maskedIdentifier: 'xx4242',
              createdAt: DateTime.utc(2026, 9, 1),
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
      await EncryptedBackupService(database: backupDatabase).exportToDocument(
        gateway: document,
        suggestedName: 'synthetic.ptrack',
        mimeType: 'application/octet-stream',
        passphrase: 'device recovery test passphrase',
      );

      final result = await DatabaseRecoveryService(
        directory: testDirectory,
        passphrases: generationKeys,
        documents: document,
      ).restoreFromDocument(passphrase: 'device recovery test passphrase');

      expect(result?.paymentSourceCount, 1);
      generationId = await generationKeys.getActiveGenerationId();
      expect(generationId, isNotNull);
      const restartedProvider = AndroidKeystoreDatabasePassphraseProvider();
      expect(await restartedProvider.getActiveGenerationId(), generationId);
      expect(await restartedProvider.getStagingGenerationIds(), isEmpty);
      final config = await resolveActiveDatabaseConfig(
        directory: testDirectory,
        passphrases: restartedProvider,
      );
      expect(config.generationId, generationId);
      final reopenedPassphrase =
          await restartedProvider.getGenerationPassphrase(generationId!);
      expect(reopenedPassphrase.value, config.passphrase.value);
      final reopened = AppDatabase(
        openEncryptedDatabase(file: config.file, passphrase: config.passphrase),
      );
      restored = reopened;
      expect(
        (await reopened.customSelect('PRAGMA cipher_version').get()),
        isNotEmpty,
      );
      expect(
        await reopened.select(reopened.paymentSources).get(),
        hasLength(1),
      );
      expect(
        await oldDatabase.readAsBytes(),
        [0x50, 0x52, 0x45, 0x56, 0x49, 0x4f, 0x55, 0x53],
      );
      final archivedLegacyFile = File(
        '${testDirectory.path}/database-recovery-archive/$generationId/paisatrack.db',
      );
      expect(
        await archivedLegacyFile.readAsBytes(),
        await oldDatabase.readAsBytes(),
      );
    } finally {
      await restored?.close();
      await backupDatabase.close();
      final createdIds = (await generationKeys.getGenerationIds())
          .difference(initialGenerationIds);
      final createdId =
          generationId ?? (createdIds.isEmpty ? null : createdIds.first);
      if (createdId != null) {
        if (await generationKeys.getActiveGenerationId() == createdId) {
          // The test began with an empty registry, so clear only its own slot.
          await generationKeys.clearAllGenerationPassphrases();
        } else {
          await generationKeys.deleteGenerationPassphrase(createdId);
        }
      }
      if (await testDirectory.exists()) {
        await testDirectory.delete(recursive: true);
      }
    }
  });
}
