import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/core/platform/recovery_qa_identity.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recovery_qa_fixture_support.dart';

const _sentinelSourceId = 't179a_synthetic_qa_source';
const _sentinelTransactionId = 't179a_synthetic_qa_transaction';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('verifies a restored synthetic database through production providers',
      () async {
    // This attestation is deliberately the first platform or filesystem action.
    await verifyRecoveryQaIdentity();

    final directory = await getApplicationDocumentsDirectory();
    final manifest = await readRecoveryQaManifest(directory);
    expect(manifest['sentinelSourceId'], _sentinelSourceId);
    expect(manifest['sentinelTransactionId'], _sentinelTransactionId);

    const passphrases = AndroidKeystoreDatabasePassphraseProvider();
    final activeGenerationId = await passphrases.getActiveGenerationId();
    expect(activeGenerationId, isNotNull);
    expect(AppDatabaseGeneration.isValidId(activeGenerationId!), isTrue);
    final generationIds = await passphrases.getGenerationIds();
    final stagingGenerationIds = await passphrases.getStagingGenerationIds();
    expect(generationIds, {activeGenerationId});
    expect(stagingGenerationIds, isEmpty);
    final legacyPassphrase = await passphrases.getPassphrase();
    final legacyPassphraseFingerprint =
        sha256.convert(utf8.encode(legacyPassphrase.value)).toString();
    expect(
      legacyPassphraseFingerprint,
      manifest['qaLegacyPassphraseSha256AfterLoss'],
    );

    final legacyFile = File(p.join(directory.path, appDatabaseFileName));
    final expectedLegacyHashes =
        readRecoveryQaHashMap(manifest['legacyDatabaseFamilySha256']);
    final actualLegacyHashes = await hashDatabaseFamily(legacyFile);
    expect(actualLegacyHashes, expectedLegacyHashes);

    final archive = File(
      p.join((await getTemporaryDirectory()).path, recoveryQaArchiveName),
    );
    final archiveSha256 = await sha256File(archive);
    expect(archiveSha256, manifest['archiveSha256']);

    final archiveDirectory = Directory(
      p.join(
        directory.path,
        'database-recovery-archive',
        activeGenerationId,
      ),
    );
    final preservedHashes = await hashDatabaseFamily(
      File(p.join(archiveDirectory.path, appDatabaseFileName)),
    );
    expect(preservedHashes, expectedLegacyHashes);

    // A fresh ProviderContainer exercises the actual appDatabaseProvider and
    // configured encrypted database. No test provider or error screen is used.
    final container = ProviderContainer();
    AppDatabase? database;
    try {
      final restoredDatabase = await container.read(appDatabaseProvider.future);
      database = restoredDatabase;
      final source =
          await (restoredDatabase.select(restoredDatabase.paymentSources)
                ..where((row) => row.id.equals(_sentinelSourceId)))
              .getSingle();
      expect(source.maskedIdentifier, 'xx4242');

      final transaction =
          await (restoredDatabase.select(restoredDatabase.transactions)
                ..where((row) => row.id.equals(_sentinelTransactionId)))
              .getSingle();
      expect(transaction.amount, 4242.0);
      expect(transaction.paymentSourceId, _sentinelSourceId);
      expect(transaction.merchantRaw, 'Synthetic Recovery QA Purchase');

      final integrityRows =
          await restoredDatabase.customSelect('PRAGMA integrity_check').get();
      expect(integrityRows, hasLength(1));
      final integrityOk =
          integrityRows.single.read<String>('integrity_check') == 'ok';
      expect(integrityOk, isTrue);
      final foreignKeyIssues =
          await restoredDatabase.customSelect('PRAGMA foreign_key_check').get();
      expect(foreignKeyIssues, isEmpty);

      emitRecoveryQaMarker('RECOVERY_QA_VERIFIED', {
        'activeGenerationId': activeGenerationId,
        'legacyDatabaseFamilyMatches':
            recoveryQaHashMapsEqual(actualLegacyHashes, expectedLegacyHashes),
        'preservedLegacyCopyMatches':
            recoveryQaHashMapsEqual(preservedHashes, expectedLegacyHashes),
        'archiveSha256Matches': archiveSha256 == manifest['archiveSha256'],
        'qaLegacyPassphraseContinuitySha256Matches':
            legacyPassphraseFingerprint ==
                manifest['qaLegacyPassphraseSha256AfterLoss'],
        'sentinelRows': {'transactions': 1, 'paymentSources': 1},
        'integrityCheck': 'ok',
        'foreignKeyIssues': foreignKeyIssues.length,
        'stagingGenerations': stagingGenerationIds.length,
      });
    } finally {
      if (database != null) await closeAppDatabase(database);
      container.dispose();
    }
  });
}
