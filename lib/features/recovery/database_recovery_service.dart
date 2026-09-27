import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/crypto/database_cipher.dart';
import '../../core/platform/system_document_gateway.dart';
import '../../data/db/database.dart';
import '../../data/db/database_file_lock.dart';
import '../../data/db/database_provider.dart';
import '../backup/encrypted_backup_service.dart';

class DatabaseRecoveryResult {
  const DatabaseRecoveryResult({
    required this.transactionCount,
    required this.paymentSourceCount,
    required this.preservedFiles,
  });

  final int transactionCount;
  final int paymentSourceCount;
  final int preservedFiles;
}

typedef RecoveryArchiveCopy = Future<File> Function(
  File source,
  String targetPath,
);
typedef RecoveryGenerationCleanup = Future<void> Function(File databaseFile);

/// Restores to a new encrypted generation and only publishes it after all
/// archive and SQL integrity checks pass. Existing database bytes and their
/// original Keystore slot are retained.
class DatabaseRecoveryService {
  const DatabaseRecoveryService({
    required this.directory,
    required this.passphrases,
    required this.documents,
    this.databaseFactory,
    this.archiveCopy,
    this.generationCleanup,
  });

  final Directory directory;
  final GenerationDatabasePassphraseProvider passphrases;
  final SystemDocumentGateway documents;
  final AppDatabase Function(File file, DatabasePassphrase passphrase)?
      databaseFactory;
  final RecoveryArchiveCopy? archiveCopy;
  final RecoveryGenerationCleanup? generationCleanup;

  Future<DatabaseRecoveryResult?> restoreFromDocument({
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    if (passphrase.trim().isEmpty) {
      throw const EncryptedBackupException('Passphrase is required');
    }

    final generationId = _newGenerationId();
    final generation = AppDatabaseGeneration(generationId);
    final databaseFile = File(p.join(directory.path, generation.fileName));
    var keySlotAttempted = false;
    var activationAttempted = false;
    AppDatabase? database;

    try {
      keySlotAttempted = true;
      final databasePassphrase = await passphrases.createGenerationPassphrase(
        generationId,
      );
      database = databaseFactory?.call(databaseFile, databasePassphrase) ??
          AppDatabase(
            openEncryptedDatabase(
              file: databaseFile,
              passphrase: databasePassphrase,
            ),
          );
      await database.seedDefaultCategories();
      await database.seedDefaultFeatureFlags();

      final imported =
          await EncryptedBackupService(database: database).importFromDocument(
        gateway: documents,
        mimeType: 'application/octet-stream',
        passphrase: passphrase,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      if (!imported) return null;

      final transactionCount = await _countRows(database, 'transactions');
      final paymentSourceCount = await _countRows(database, 'payment_sources');
      await _assertDatabaseIntegrity(database);
      await closeAppDatabase(database);
      database = null;

      final preservedFiles = await withDatabaseFileLock(directory, () async {
        final copiedFiles = await _preserveCurrentDatabase(generationId);
        activationAttempted = true;
        try {
          await passphrases.activateGeneration(generationId);
        } on Object {
          if (!await _isActiveGeneration(generationId)) rethrow;
        }
        return copiedFiles;
      });

      return DatabaseRecoveryResult(
        transactionCount: transactionCount,
        paymentSourceCount: paymentSourceCount,
        preservedFiles: preservedFiles,
      );
    } finally {
      if (database != null) await closeAppDatabase(database);
      // Once activation is attempted, preserve the complete database and key
      // even if the method-channel result is ambiguous. Startup can determine
      // which generation is active from the durable native pointer.
      if (!activationAttempted) {
        var familyRemoved = false;
        try {
          await (generationCleanup ?? _deleteDatabaseFamily)(databaseFile);
          familyRemoved = true;
        } on Object {
          // An orphan staging file is safe and can be retried or cleaned later.
        }
        if (keySlotAttempted && familyRemoved) {
          try {
            await passphrases.deleteGenerationPassphrase(generationId);
          } on Object {
            // Keep any orphan key slot; it is not selected as active.
          }
        }
      }
    }
  }

  Future<void> _assertDatabaseIntegrity(AppDatabase database) async {
    final integrityRows =
        await database.customSelect('PRAGMA integrity_check').get();
    if (integrityRows.length != 1 ||
        integrityRows.single.read<String>('integrity_check') != 'ok') {
      throw const EncryptedBackupException(
        'Restored database failed integrity check',
      );
    }
    final foreignKeyErrors =
        await database.customSelect('PRAGMA foreign_key_check').get();
    if (foreignKeyErrors.isNotEmpty) {
      throw const EncryptedBackupException(
        'Restored database contains invalid references',
      );
    }
  }

  Future<int> _countRows(AppDatabase database, String table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS row_count FROM "$table"')
        .getSingle();
    return row.read<int>('row_count');
  }

  Future<bool> _isActiveGeneration(String generationId) async {
    try {
      return await passphrases.getActiveGenerationId() == generationId;
    } on Object {
      return false;
    }
  }

  Future<int> _preserveCurrentDatabase(String generationId) async {
    final activeGenerationId = await passphrases.getActiveGenerationId();
    if (activeGenerationId != null &&
        !AppDatabaseGeneration.isValidId(activeGenerationId)) {
      throw const DatabaseKeyLostError('Active database generation is invalid');
    }
    final currentFile = File(
      p.join(
        directory.path,
        activeGenerationId == null
            ? appDatabaseFileName
            : AppDatabaseGeneration(activeGenerationId).fileName,
      ),
    );
    final archiveDirectory = Directory(
      p.join(directory.path, 'database-recovery-archive', generationId),
    );
    var copied = 0;
    final fileNames = [
      currentFile.path,
      '${currentFile.path}-wal',
      '${currentFile.path}-shm',
      '${currentFile.path}-journal',
    ];
    try {
      for (final sourcePath in fileNames) {
        final source = File(sourcePath);
        if (!await source.exists()) continue;
        await archiveDirectory.create(recursive: true);
        final target = File(
          p.join(archiveDirectory.path, p.basename(sourcePath)),
        );
        final sourceDigestBefore = await _digest(source);
        final copy = archiveCopy ?? (source, path) => source.copy(path);
        await copy(source, target.path);
        final sourceDigestAfter = await _digest(source);
        final targetDigest = await _digest(target);
        if (sourceDigestBefore != sourceDigestAfter ||
            sourceDigestBefore != targetDigest ||
            await source.length() != await target.length()) {
          throw const FileSystemException(
            'Database files changed while the recovery copy was being verified',
          );
        }
        copied++;
      }
      return copied;
    } on Object {
      try {
        if (await archiveDirectory.exists()) {
          await archiveDirectory.delete(recursive: true);
        }
        final archiveRoot = archiveDirectory.parent;
        if (await archiveRoot.exists() && await archiveRoot.list().isEmpty) {
          await archiveRoot.delete();
        }
      } on Object {
        // Archive cleanup is best-effort; the original database is untouched.
      }
      rethrow;
    }
  }

  Future<String> _digest(File file) async {
    final algorithm = Sha256();
    final sink = algorithm.newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _deleteDatabaseFamily(File file) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final candidate = File('${file.path}$suffix');
      if (await candidate.exists()) await candidate.delete();
    }
  }

  String _newGenerationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

final databaseRecoveryServiceProvider = FutureProvider<DatabaseRecoveryService>(
  (ref) async {
    final passphraseProvider = ref.watch(databasePassphraseProvider);
    if (passphraseProvider is! GenerationDatabasePassphraseProvider) {
      throw StateError('Generation database key provider is unavailable');
    }
    return DatabaseRecoveryService(
      directory: await ref.watch(databaseDirectoryProvider.future),
      passphrases: passphraseProvider,
      documents: ref.watch(systemDocumentGatewayProvider),
    );
  },
);
