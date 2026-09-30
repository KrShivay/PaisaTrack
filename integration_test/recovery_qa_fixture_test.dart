import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/core/platform/system_document_gateway.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/backup/encrypted_backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recovery_qa_fixture_support.dart';

const _archivePassphrase = 'T179a synthetic QA archive passphrase';
const _sentinelSourceId = 't179a_synthetic_qa_source';
const _sentinelTransactionId = 't179a_synthetic_qa_transaction';
const _archiveName = recoveryQaArchiveName;

class _MemorySaveGateway extends SystemDocumentGateway {
  _MemorySaveGateway() : super();

  final _bytes = BytesBuilder(copy: false);

  Uint8List get bytes => _bytes.takeBytes();

  @override
  Future<String?> beginSaveDocument({
    required String suggestedName,
    required String mimeType,
  }) async =>
      'synthetic-save';

  @override
  Future<bool> writeDocumentChunk({
    required String sessionId,
    required Uint8List bytes,
  }) async {
    _bytes.add(bytes);
    return true;
  }

  @override
  Future<bool> finishDocument({required String sessionId}) async => true;

  @override
  Future<void> cancelDocument({required String sessionId}) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('prepares a synthetic QA lost-key recovery fixture', () async {
    // This attestation is deliberately the first platform or filesystem action.
    await verifyRecoveryQaIdentity();

    const passphrases = AndroidKeystoreDatabasePassphraseProvider();
    expect(await passphrases.getGenerationIds(), isEmpty);
    expect(await passphrases.getStagingGenerationIds(), isEmpty);
    expect(await passphrases.getActiveGenerationId(), isNull);

    final directory = await getApplicationDocumentsDirectory();
    final legacyFile = File(p.join(directory.path, appDatabaseFileName));
    expect(
      await hashDatabaseFamily(legacyFile),
      isEmpty,
      reason: 'Use a fresh recovery QA identity; existing data is never reset.',
    );
    final existingGenerationFiles =
        await directory.list(followLinks: false).where((entry) {
      if (entry is! File) return false;
      return RegExp(
        r'^paisatrack\.[0-9a-f-]{36}\.db(?:-(?:wal|shm|journal))?$',
      ).hasMatch(p.basename(entry.path));
    }).toList();
    expect(existingGenerationFiles, isEmpty);

    final legacyPassphrase = await passphrases.getPassphrase();
    final database = AppDatabase(
      openEncryptedDatabase(file: legacyFile, passphrase: legacyPassphrase),
    );
    final gateway = _MemorySaveGateway();
    try {
      await database.seedDefaultCategories();
      await database.seedDefaultFeatureFlags();
      await database.into(database.paymentSources).insert(
            PaymentSourcesCompanion.insert(
              id: _sentinelSourceId,
              kind: 'card',
              maskedIdentifier: 'xx4242',
              createdAt: DateTime.utc(2026, 10, 1),
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          );
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: _sentinelTransactionId,
              ts: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
              amount: 4242.0,
              direction: 'debit',
              channel: 'card',
              paymentSourceId: const Value(_sentinelSourceId),
              merchantRaw: const Value('Synthetic Recovery QA Purchase'),
              description: const Value('Recovery QA sentinel transaction'),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: DateTime.utc(2026, 10, 1),
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          );
      final exported =
          await EncryptedBackupService(database: database).exportToDocument(
        gateway: gateway,
        suggestedName: _archiveName,
        mimeType: 'application/octet-stream',
        passphrase: _archivePassphrase,
      );
      expect(exported, isTrue);
    } finally {
      await database.close();
    }

    final archive =
        File(p.join((await getTemporaryDirectory()).path, _archiveName));
    final archiveBytes = gateway.bytes;
    expect(archiveBytes, isNotEmpty);
    await archive.writeAsBytes(archiveBytes, flush: true);
    final databaseBeforeReset = await hashDatabaseFamily(legacyFile);
    expect(databaseBeforeReset, isNotEmpty);
    final originalPassphraseFingerprint =
        sha256.convert(utf8.encode(legacyPassphrase.value)).toString();

    // Registry emptiness was checked before the first key call. This QA-only
    // reset deletes the legacy key and leaves this synthetic DB intact.
    await passphrases.debugResetForTests();
    // Production startup will create this replacement legacy key before it
    // fails to decrypt the still-old-key DB and routes to KeyLossScreen.
    final replacementPassphrase = await passphrases.getPassphrase();
    final replacementPassphraseFingerprint =
        sha256.convert(utf8.encode(replacementPassphrase.value)).toString();
    expect(
      replacementPassphraseFingerprint,
      isNot(originalPassphraseFingerprint),
    );

    final databaseAfterReset = await hashDatabaseFamily(legacyFile);
    expect(databaseAfterReset, databaseBeforeReset);

    await writeRecoveryQaManifest(directory, {
      'version': recoveryQaManifestVersion,
      'archiveName': _archiveName,
      'archiveSha256': await sha256File(archive),
      'legacyDatabaseFamilySha256': databaseAfterReset,
      // This hashes the synthetic passphrase value, not a native alias.
      'qaLegacyPassphraseSha256AfterLoss': replacementPassphraseFingerprint,
      'sentinelSourceId': _sentinelSourceId,
      'sentinelTransactionId': _sentinelTransactionId,
    });

    emitRecoveryQaMarker('RECOVERY_QA_PREPARED', {
      'archiveName': _archiveName,
      'archiveSha256': await sha256File(archive),
      'legacyDatabaseFamilySha256': databaseAfterReset,
      'qaLegacyPassphraseSha256AfterLoss': replacementPassphraseFingerprint,
      'syntheticRows': {'transactions': 1, 'paymentSources': 1},
    });
  });
}
