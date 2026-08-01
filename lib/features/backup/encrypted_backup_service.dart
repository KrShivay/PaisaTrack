import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../capture/parser_version.dart';
import '../../core/platform/system_document_gateway.dart';

const encryptedBackupFileName = 'paisatrack_export.ptrack';
const encryptedBackupMaxBytes = 32 * 1024 * 1024;
const encryptedBackupMaxCiphertextBytes = 16 * 1024 * 1024;
const encryptedBackupMaxRowsPerTable = 50 * 1000;
const encryptedBackupMaxRowsTotal = 200 * 1000;
// Leaves room for the binary record tag, length, and GCM MAC inside the
// platform gateway's 64 KiB message ceiling.
const encryptedBackupChunkSize = 60 * 1024;
const _argon2MemoryKiB = 19456;
const _argon2Parallelism = 1;
const _argon2Iterations = 2;
const _argon2HashLength = 32;
const _argon2MaxParallelism = 4;
const _argon2MaxIterations = 10;
const _aes256KeyLength = 32;
const _aesGcmMacLength = 16;
const _chunkedBackupMagic = <int>[0x50, 0x54, 0x52, 0x4b]; // PTRK
const _chunkedBackupVersion = 2;
const _chunkedHeaderMaxBytes = 64 * 1024;
const _archiveRowPageSize = 256;

enum EncryptedBackupProgressPhase {
  preparing,
  encrypting,
  decrypting,
  restoring,
  completed,
}

class EncryptedBackupProgress {
  const EncryptedBackupProgress({
    required this.phase,
    required this.processedRows,
    required this.totalRows,
    required this.processedBytes,
    required this.totalBytes,
  });

  final EncryptedBackupProgressPhase phase;
  final int processedRows;
  final int totalRows;
  final int processedBytes;
  final int? totalBytes;
}

typedef EncryptedBackupProgressCallback = void Function(
  EncryptedBackupProgress progress,
);

class EncryptedBackupCancellation {
  EncryptedBackupCancellation();

  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Resource ceilings applied before archive parsing/restoration.
class EncryptedBackupLimits {
  const EncryptedBackupLimits({
    this.maxEncryptedBytes = encryptedBackupMaxBytes,
    this.maxCiphertextBytes = encryptedBackupMaxCiphertextBytes,
    this.maxRowsPerTable = encryptedBackupMaxRowsPerTable,
    this.maxRowsTotal = encryptedBackupMaxRowsTotal,
  });

  final int maxEncryptedBytes;
  final int maxCiphertextBytes;
  final int maxRowsPerTable;
  final int maxRowsTotal;
}

class EncryptedBackupException implements Exception {
  const EncryptedBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EncryptedBackupService {
  EncryptedBackupService({
    required AppDatabase database,
    Random? random,
    Argon2id? kdf,
    AesGcm? cipher,
    DateTime Function()? clock,
    EncryptedBackupLimits limits = const EncryptedBackupLimits(),
  })  : _database = database,
        _random = random ?? Random.secure(),
        _kdf = kdf ??
            Argon2id(
              memory: _argon2MemoryKiB,
              parallelism: _argon2Parallelism,
              iterations: _argon2Iterations,
              hashLength: _argon2HashLength,
            ),
        _cipher = cipher ?? AesGcm.with256bits(),
        _clock = clock ?? DateTime.now,
        _limits = limits;

  final AppDatabase _database;
  final Random _random;
  final Argon2id _kdf;
  static const minimumPassphraseLength = 12;
  final AesGcm _cipher;
  final DateTime Function() _clock;
  final EncryptedBackupLimits _limits;

  Future<File> exportToFile({
    required Directory directory,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, encryptedBackupFileName));
    try {
      await _exportChunkedFile(
        file: file,
        passphrase: passphrase,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
    return file;
  }

  /// Streams a new authenticated backup through the Android document picker.
  ///
  /// The picker receives bounded chunks and never receives the complete
  /// encrypted archive in a platform-channel message.
  Future<bool> exportToDocument({
    required SystemDocumentGateway gateway,
    required String suggestedName,
    required String mimeType,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    final sessionId = await gateway.beginSaveDocument(
      suggestedName: suggestedName,
      mimeType: mimeType,
    );
    if (sessionId == null) return false;
    try {
      await _exportChunkedToSink(
        writeChunk: (bytes) async {
          final accepted = await gateway.writeDocumentChunk(
            sessionId: sessionId,
            bytes: Uint8List.fromList(bytes),
          );
          if (!accepted) {
            throw const EncryptedBackupException(
              'Document write failed',
            );
          }
        },
        finishSink: () async {
          final finished = await gateway.finishDocument(sessionId: sessionId);
          if (!finished) {
            throw const EncryptedBackupException('Document write failed');
          }
        },
        closeSink: () => gateway.cancelDocument(sessionId: sessionId),
        passphrase: passphrase,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return true;
    } catch (_) {
      await gateway.cancelDocument(sessionId: sessionId);
      rethrow;
    }
  }

  /// Builds the encrypted archive in memory for a system document destination.
  Future<Uint8List> exportBytes({required String passphrase}) async {
    _assertExportPassphrase(passphrase);
    _assertKnownKdfProfile(_kdf);
    final archive = await _readArchive();
    final plaintext = utf8.encode(jsonEncode(archive));
    _assertCiphertextSize(plaintext.length);
    final payload = await _encrypt(
      plaintext,
      passphrase: passphrase,
    );
    final encodedPayload = utf8.encode(jsonEncode(payload));
    _assertEncryptedSize(encodedPayload.length);
    return Uint8List.fromList(encodedPayload);
  }

  void _assertExportPassphrase(String passphrase) {
    if (passphrase.runes.length < minimumPassphraseLength) {
      throw const EncryptedBackupException(
        'Passphrase must be at least $minimumPassphraseLength characters long',
      );
    }
  }

  Future<void> importFromFile({
    required File file,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    if (!await file.exists()) {
      throw const EncryptedBackupException('Encrypted export file not found');
    }

    final length = await file.length();
    _assertEncryptedSize(length);
    final prefix = await _readPrefix(file, _chunkedBackupMagic.length);
    if (_isChunkedBackup(prefix)) {
      await _importChunkedStream(
        stream: file.openRead(),
        passphrase: passphrase,
        encryptedBytes: length,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return;
    }
    await importBytes(
      bytes: await file.readAsBytes(),
      passphrase: passphrase,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  /// Imports either a legacy v1 envelope or the streamed envelope from a
  /// bounded Android document-reader session.
  Future<bool> importFromDocument({
    required SystemDocumentGateway gateway,
    required String mimeType,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    if (passphrase.isEmpty) {
      throw const EncryptedBackupException('Passphrase is required');
    }
    final sessionId = await gateway.beginOpenDocument(mimeType: mimeType);
    if (sessionId == null) return false;
    try {
      final firstChunk = await _readDocumentPrefix(
        gateway: gateway,
        sessionId: sessionId,
        cancellation: cancellation,
      );
      final stream = _documentStream(
        gateway: gateway,
        sessionId: sessionId,
        firstChunk: firstChunk,
        cancellation: cancellation,
      );
      if (_isChunkedBackup(firstChunk)) {
        await _importChunkedStream(
          stream: stream,
          passphrase: passphrase,
          encryptedBytes: null,
          onProgress: onProgress,
          cancellation: cancellation,
        );
      } else {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          bytes.add(chunk);
          if (bytes.length > _limits.maxEncryptedBytes) {
            throw const EncryptedBackupException(
              'Encrypted backup exceeds the maximum file size',
            );
          }
        }
        await importBytes(
          bytes: bytes.takeBytes(),
          passphrase: passphrase,
          onProgress: onProgress,
          cancellation: cancellation,
        );
      }
      return true;
    } finally {
      await gateway.closeDocument(sessionId: sessionId);
    }
  }

  Future<Uint8List> _readDocumentPrefix({
    required SystemDocumentGateway gateway,
    required String sessionId,
    required EncryptedBackupCancellation? cancellation,
  }) async {
    final prefix = BytesBuilder(copy: false);
    while (prefix.length < _chunkedBackupMagic.length) {
      _checkCancellation(cancellation);
      final chunk = await gateway.readDocumentChunk(sessionId: sessionId);
      if (chunk == null || chunk.isEmpty) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      prefix.add(chunk);
    }
    return prefix.takeBytes();
  }

  Stream<List<int>> _documentStream({
    required SystemDocumentGateway gateway,
    required String sessionId,
    required Uint8List firstChunk,
    required EncryptedBackupCancellation? cancellation,
  }) async* {
    yield firstChunk;
    while (true) {
      _checkCancellation(cancellation);
      final chunk = await gateway.readDocumentChunk(sessionId: sessionId);
      if (chunk == null) return;
      if (chunk.isEmpty || chunk.length > maxDocumentChunkBytes) {
        throw const EncryptedBackupException('Document read failed');
      }
      yield chunk;
    }
  }

  /// Restores an encrypted archive selected through the system picker.
  Future<void> importBytes({
    required Uint8List bytes,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    if (passphrase.isEmpty) {
      throw const EncryptedBackupException('Passphrase is required');
    }
    _assertEncryptedSize(bytes.length);
    if (_isChunkedBackup(bytes)) {
      await _importChunkedStream(
        stream: Stream<List<int>>.value(bytes),
        passphrase: passphrase,
        encryptedBytes: bytes.length,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return;
    }
    final payload = _decodeJsonMap(bytes);
    final plaintext = await _decrypt(payload, passphrase: passphrase);
    _assertCiphertextSize(plaintext.length);
    final archive = _decodeJsonMap(plaintext);
    _validateArchive(archive);

    try {
      await _restoreArchive(archive, now: _clock().toUtc());
    } on TypeError catch (e) {
      throw EncryptedBackupException('Malformed archive table row: $e');
    }
  }

  Future<void> _exportChunkedFile({
    required File file,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    _assertExportPassphrase(passphrase);
    _assertKnownKdfProfile(_kdf);
    _checkCancellation(cancellation);

    final now = _clock().toUtc();
    final totalRows = await _countRetainedArchiveRows(now);
    onProgress?.call(
      EncryptedBackupProgress(
        phase: EncryptedBackupProgressPhase.preparing,
        processedRows: 0,
        totalRows: totalRows,
        processedBytes: 0,
        totalBytes: null,
      ),
    );

    final salt = _randomBytes(16);
    final baseNonce = _randomBytes(AesGcm.defaultNonceLength);
    final kdf = {
      'name': 'argon2id',
      'memory': _kdf.memory,
      'parallelism': _kdf.parallelism,
      'iterations': _kdf.iterations,
      'hash_length': _kdf.hashLength,
      'salt': base64Encode(salt),
    };
    final header = <String, Object?>{
      'format': 'paisatrack-chunked-backup',
      'version': _chunkedBackupVersion,
      'archive_version': 3,
      'archive_encoding': 'ndjson',
      'chunk_size': encryptedBackupChunkSize,
      'kdf': kdf,
      'base_nonce': base64Encode(baseNonce),
    };
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
    if (headerBytes.length > _chunkedHeaderMaxBytes) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    final key = await _deriveKey(passphrase, salt);
    final sink = file.openWrite();
    late final _ChunkedBackupWriter writer;
    writer = _ChunkedBackupWriter(
      writeChunk: (bytes) async => sink.add(bytes),
      cipher: AesGcm.with256bits(),
      key: key,
      headerBytes: headerBytes,
      baseNonce: baseNonce,
      maxPlaintextBytes: _limits.maxCiphertextBytes,
      maxEncryptedBytes: _limits.maxEncryptedBytes,
      cancellation: cancellation,
      onProgress: (bytes) {
        onProgress?.call(
          EncryptedBackupProgress(
            phase: EncryptedBackupProgressPhase.encrypting,
            processedRows: writer.processedRows,
            totalRows: totalRows,
            processedBytes: bytes,
            totalBytes: null,
          ),
        );
      },
    );

    try {
      await writer.writeHeader();
      var processedRows = 0;
      await _writeArchiveNdjson(
        write: writer.add,
        now: now,
        onRows: (count) {
          processedRows = count;
          writer.processedRows = count;
          _checkCancellation(cancellation);
        },
      );
      if (processedRows != totalRows) {
        throw const EncryptedBackupException(
          'Encrypted backup changed while it was being exported',
        );
      }
      await writer.finish();
      await sink.flush();
      onProgress?.call(
        EncryptedBackupProgress(
          phase: EncryptedBackupProgressPhase.completed,
          processedRows: totalRows,
          totalRows: totalRows,
          processedBytes: writer.encryptedBytesWritten,
          totalBytes: writer.encryptedBytesWritten,
        ),
      );
    } finally {
      await sink.close();
    }
  }

  Future<void> _exportChunkedToSink({
    required Future<void> Function(List<int> bytes) writeChunk,
    required Future<void> Function() finishSink,
    required Future<void> Function() closeSink,
    required String passphrase,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    _assertExportPassphrase(passphrase);
    _assertKnownKdfProfile(_kdf);
    _checkCancellation(cancellation);
    final now = _clock().toUtc();
    final totalRows = await _countRetainedArchiveRows(now);
    onProgress?.call(
      EncryptedBackupProgress(
        phase: EncryptedBackupProgressPhase.preparing,
        processedRows: 0,
        totalRows: totalRows,
        processedBytes: 0,
        totalBytes: null,
      ),
    );
    final salt = _randomBytes(16);
    final baseNonce = _randomBytes(AesGcm.defaultNonceLength);
    final header = <String, Object?>{
      'format': 'paisatrack-chunked-backup',
      'version': _chunkedBackupVersion,
      'archive_version': 3,
      'archive_encoding': 'ndjson',
      'chunk_size': encryptedBackupChunkSize,
      'kdf': {
        'name': 'argon2id',
        'memory': _kdf.memory,
        'parallelism': _kdf.parallelism,
        'iterations': _kdf.iterations,
        'hash_length': _kdf.hashLength,
        'salt': base64Encode(salt),
      },
      'base_nonce': base64Encode(baseNonce),
    };
    final headerBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
    if (headerBytes.length > _chunkedHeaderMaxBytes) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    final key = await _deriveKey(passphrase, salt);
    late final _ChunkedBackupWriter writer;
    writer = _ChunkedBackupWriter(
      writeChunk: writeChunk,
      cipher: AesGcm.with256bits(),
      key: key,
      headerBytes: headerBytes,
      baseNonce: baseNonce,
      maxPlaintextBytes: _limits.maxCiphertextBytes,
      maxEncryptedBytes: _limits.maxEncryptedBytes,
      cancellation: cancellation,
      onProgress: (bytes) {
        onProgress?.call(
          EncryptedBackupProgress(
            phase: EncryptedBackupProgressPhase.encrypting,
            processedRows: writer.processedRows,
            totalRows: totalRows,
            processedBytes: bytes,
            totalBytes: null,
          ),
        );
      },
    );
    try {
      await writer.writeHeader();
      var processedRows = 0;
      await _writeArchiveNdjson(
        write: writer.add,
        now: now,
        onRows: (count) {
          processedRows = count;
          writer.processedRows = count;
          _checkCancellation(cancellation);
        },
      );
      if (processedRows != totalRows) {
        throw const EncryptedBackupException(
          'Encrypted backup changed while it was being exported',
        );
      }
      await writer.finish();
      await finishSink();
      onProgress?.call(
        EncryptedBackupProgress(
          phase: EncryptedBackupProgressPhase.completed,
          processedRows: totalRows,
          totalRows: totalRows,
          processedBytes: writer.encryptedBytesWritten,
          totalBytes: writer.encryptedBytesWritten,
        ),
      );
    } finally {
      await closeSink();
    }
  }

  Future<void> _importChunkedStream({
    required Stream<List<int>> stream,
    required String passphrase,
    required int? encryptedBytes,
    EncryptedBackupProgressCallback? onProgress,
    EncryptedBackupCancellation? cancellation,
  }) async {
    if (encryptedBytes != null) _assertEncryptedSize(encryptedBytes);
    _checkCancellation(cancellation);
    final reader = _ChunkedBackupReader(stream);
    try {
      final header = await reader.readHeader();
      _assertEncryptedSize(reader.bytesRead);
      final kdf = header['kdf'];
      final baseNonceEncoded = header['base_nonce'];
      if (kdf is! Map || baseNonceEncoded is! String) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final kdfMap = Map<String, Object?>.from(kdf);
      if (header['archive_version'] != 3 ||
          header['archive_encoding'] != 'ndjson' ||
          header['chunk_size'] != encryptedBackupChunkSize ||
          kdfMap['name'] != 'argon2id') {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final memory = _boundedInt(
        kdfMap['memory'],
        min: _argon2MemoryKiB,
        max: _argon2MemoryKiB,
      );
      final parallelism = _boundedInt(
        kdfMap['parallelism'],
        min: 1,
        max: _argon2MaxParallelism,
      );
      final iterations = _boundedInt(
        kdfMap['iterations'],
        min: 1,
        max: _argon2MaxIterations,
      );
      final hashLength = _boundedInt(
        kdfMap['hash_length'],
        min: _aes256KeyLength,
        max: _aes256KeyLength,
      );
      if (memory != _argon2MemoryKiB ||
          parallelism != _argon2Parallelism ||
          iterations != _argon2Iterations ||
          hashLength != _argon2HashLength) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final salt = base64Decode(kdfMap['salt']! as String);
      final baseNonce = base64Decode(baseNonceEncoded);
      if (salt.length < 16 ||
          salt.length > 64 ||
          baseNonce.length != AesGcm.defaultNonceLength) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final payloadKdf = Argon2id(
        memory: memory,
        parallelism: parallelism,
        iterations: iterations,
        hashLength: hashLength,
      );
      final key = await _deriveKey(passphrase, salt, kdf: payloadKdf);
      late final _ChunkedArchiveRestorer restorer;
      restorer = _ChunkedArchiveRestorer(
        database: _database,
        now: _clock().toUtc(),
        maxRowsPerTable: _limits.maxRowsPerTable,
        maxRowsTotal: _limits.maxRowsTotal,
        onRows: (count) {
          onProgress?.call(
            EncryptedBackupProgress(
              phase: EncryptedBackupProgressPhase.restoring,
              processedRows: count,
              totalRows: 0,
              processedBytes: reader.bytesRead,
              totalBytes: encryptedBytes,
            ),
          );
        },
      );
      var chunkCount = 0;
      var plaintextBytes = 0;
      var ciphertextBytes = 0;
      Map<String, Object?>? finalManifest;

      await _database.transaction(() async {
        await restorer.clearDatabase();
        while (true) {
          _checkCancellation(cancellation);
          final kind = await reader.readOptionalByte();
          if (kind == null) break;
          final length = await reader.readUint32();
          if (length <= 0 || length > encryptedBackupChunkSize) {
            throw const EncryptedBackupException('Invalid encrypted export');
          }
          final encryptedChunk =
              await reader.readExact(length + _aesGcmMacLength);
          _assertEncryptedSize(reader.bytesRead);
          final cipherText = encryptedChunk.sublist(0, length);
          final mac = encryptedChunk.sublist(length);
          final nonce = _chunkNonce(baseNonce, chunkCount);
          final aad = _chunkAad(reader.headerBytes, chunkCount, length, kind);
          final clearText = await AesGcm.with256bits().decrypt(
            SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
            secretKey: key,
            aad: aad,
          );

          if (kind == _ChunkedBackupWriter.dataRecord) {
            if (finalManifest != null) {
              throw const EncryptedBackupException('Invalid encrypted export');
            }
            chunkCount++;
            plaintextBytes += clearText.length;
            ciphertextBytes += cipherText.length;
            _assertCiphertextSize(plaintextBytes);
            await restorer.add(clearText);
            onProgress?.call(
              EncryptedBackupProgress(
                phase: EncryptedBackupProgressPhase.decrypting,
                processedRows: 0,
                totalRows: 0,
                processedBytes: reader.bytesRead,
                totalBytes: encryptedBytes,
              ),
            );
          } else if (kind == _ChunkedBackupWriter.manifestRecord) {
            if (finalManifest != null ||
                clearText.length > _chunkedHeaderMaxBytes) {
              throw const EncryptedBackupException('Invalid encrypted export');
            }
            final manifest = _decodeJsonMap(clearText);
            finalManifest = manifest;
            if (manifest['version'] != _chunkedBackupVersion ||
                manifest['chunks'] != chunkCount ||
                manifest['plaintext_bytes'] != plaintextBytes ||
                manifest['ciphertext_bytes'] != ciphertextBytes) {
              throw const EncryptedBackupException('Invalid encrypted export');
            }
            final trailing = await reader.readOptionalByte();
            _assertEncryptedSize(reader.bytesRead);
            if (trailing != null) {
              throw const EncryptedBackupException('Invalid encrypted export');
            }
            break;
          } else {
            throw const EncryptedBackupException('Invalid encrypted export');
          }
        }

        if (finalManifest == null || chunkCount == 0) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        await restorer.finish();
      });

      if (finalManifest == null || chunkCount == 0) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final totalRows = restorer.totalRows;
      onProgress?.call(
        EncryptedBackupProgress(
          phase: EncryptedBackupProgressPhase.completed,
          processedRows: totalRows,
          totalRows: totalRows,
          processedBytes: reader.bytesRead,
          totalBytes: encryptedBytes,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const EncryptedBackupException(
        'Wrong passphrase or corrupt export',
      );
    } on FormatException {
      throw const EncryptedBackupException('Invalid encrypted export');
    } on TypeError {
      throw const EncryptedBackupException('Invalid encrypted export');
    } on ArgumentError {
      throw const EncryptedBackupException('Invalid encrypted export');
    } finally {
      await reader.close();
    }
  }

  Future<List<int>> _readPrefix(File file, int length) async {
    final prefix = <int>[];
    await for (final chunk in file.openRead(0, length)) {
      prefix.addAll(chunk);
      if (prefix.length >= length) break;
    }
    return prefix;
  }

  bool _isChunkedBackup(List<int> bytes) {
    if (bytes.length < _chunkedBackupMagic.length) return false;
    for (var i = 0; i < _chunkedBackupMagic.length; i++) {
      if (bytes[i] != _chunkedBackupMagic[i]) return false;
    }
    return true;
  }

  void _checkCancellation(EncryptedBackupCancellation? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw const EncryptedBackupException('Backup operation cancelled');
    }
  }

  Future<int> _countRetainedArchiveRows(DateTime now) async {
    var total = 0;
    for (final tableName in _archiveTableNames) {
      final count = await _countTableRows(
        tableName,
        rawSmsAfter: tableName == 'raw_sms' ? now : null,
      );
      _assertTableRowCount(count, tableName);
      total += count;
      if (total > _limits.maxRowsTotal) {
        throw const EncryptedBackupException(
          'Encrypted backup exceeds the maximum row count',
        );
      }
    }
    return total;
  }

  Future<int> _countTableRows(
    String tableName, {
    DateTime? rawSmsAfter,
  }) async {
    final where = rawSmsAfter == null ? '' : ' WHERE purge_after > ?';
    final result = await _database.customSelect(
      'SELECT COUNT(*) AS row_count FROM "$tableName"$where',
      variables: [
        if (rawSmsAfter != null) Variable.withDateTime(rawSmsAfter),
      ],
    ).getSingle();
    return result.read<int>('row_count');
  }

  static const _archiveTableNames = [
    'categories',
    'merchants',
    'raw_sms',
    'merchant_aliases',
    'payment_sources',
    'transactions',
    'rules',
    'feedback',
    'baselines',
    'insights',
    'model_meta',
    'recurring_series',
  ];

  Future<void> _writeArchiveNdjson({
    required Future<void> Function(List<int> bytes) write,
    required DateTime now,
    required void Function(int processedRows) onRows,
  }) async {
    await write(utf8.encode('{"kind":"header","version":3}\n'));
    var processedRows = 0;
    final tableCounts = <String, int>{};

    Future<void> writeTable<T extends DataClass>(
      String tableName,
      Future<List<T>> Function(int offset, int limit) fetch,
    ) async {
      var tableRows = 0;
      await _writePagedRows(
        tableName: tableName,
        fetch: fetch,
        writeRow: (row) async {
          await write(
            utf8.encode(
              '${jsonEncode({
                    'kind': 'row',
                    'table': tableName,
                    'row': row.toJson(),
                  })}\n',
            ),
          );
          tableRows++;
          processedRows++;
          onRows(processedRows);
        },
      );
      tableCounts[tableName] = tableRows;
    }

    await writeTable(
      'categories',
      (offset, limit) => (_database.select(_database.categories)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'merchants',
      (offset, limit) => (_database.select(_database.merchants)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'raw_sms',
      (offset, limit) => (_database.select(_database.rawSms)
            ..where(
              (row) =>
                  row.purgeAfter.isNull() |
                  row.purgeAfter.isBiggerThanValue(now),
            )
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'merchant_aliases',
      (offset, limit) => (_database.select(_database.merchantAliases)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'payment_sources',
      (offset, limit) => (_database.select(_database.paymentSources)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'transactions',
      (offset, limit) => (_database.select(_database.transactions)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'rules',
      (offset, limit) => (_database.select(_database.rules)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'feedback',
      (offset, limit) => (_database.select(_database.feedback)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'baselines',
      (offset, limit) => (_database.select(_database.baselines)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'insights',
      (offset, limit) => (_database.select(_database.insights)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'model_meta',
      (offset, limit) => (_database.select(_database.modelMeta)
            ..limit(limit, offset: offset))
          .get(),
    );
    await writeTable(
      'recurring_series',
      (offset, limit) => (_database.select(_database.recurringSeries)
            ..limit(limit, offset: offset))
          .get(),
    );
    await write(
      utf8.encode(
        '${jsonEncode({
              'kind': 'footer',
              'version': _chunkedBackupVersion,
              'rows': processedRows,
              'tables': tableCounts,
            })}\n',
      ),
    );
  }

  Future<void> _writePagedRows<T extends DataClass>({
    required String tableName,
    required Future<List<T>> Function(int offset, int limit) fetch,
    required Future<void> Function(T row) writeRow,
  }) async {
    var offset = 0;
    var tableRows = 0;
    while (true) {
      final rows = await fetch(offset, _archiveRowPageSize);
      if (rows.isEmpty) break;
      tableRows += rows.length;
      _assertTableRowCount(tableRows, tableName);
      for (final row in rows) {
        await writeRow(row);
      }
      if (rows.length < _archiveRowPageSize) break;
      offset += rows.length;
    }
  }

  List<int> _chunkNonce(List<int> baseNonce, int index) {
    final nonce = Uint8List.fromList(baseNonce);
    var value = index;
    for (var i = nonce.length - 1; i >= nonce.length - 8; i--) {
      nonce[i] = value & 0xff;
      value >>= 8;
    }
    return nonce;
  }

  List<int> _chunkAad(
    List<int> headerBytes,
    int index,
    int plaintextLength,
    int kind,
  ) {
    final result = BytesBuilder(copy: false);
    result.add(headerBytes);
    result.add([kind]);
    result.add(_uint64Bytes(index));
    result.add(_uint32Bytes(plaintextLength));
    return result.takeBytes();
  }

  List<int> _uint32Bytes(int value) => [
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  List<int> _uint64Bytes(int value) {
    final bytes = Uint8List(8);
    var remaining = value;
    for (var i = 7; i >= 0; i--) {
      bytes[i] = remaining & 0xff;
      remaining >>= 8;
    }
    return bytes;
  }

  Future<Map<String, Object?>> _readArchive() async {
    final archive = {
      'version': 3,
      'tables': {
        'categories':
            await _rows(_database.categories, tableName: 'categories'),
        'merchants': await _rows(_database.merchants, tableName: 'merchants'),
        'raw_sms': await _retainedRawSmsRows(_clock().toUtc()),
        'merchant_aliases': await _rows(
          _database.merchantAliases,
          tableName: 'merchant_aliases',
        ),
        'payment_sources':
            await _rows(_database.paymentSources, tableName: 'payment_sources'),
        'transactions':
            await _rows(_database.transactions, tableName: 'transactions'),
        'rules': await _rows(_database.rules, tableName: 'rules'),
        'feedback': await _rows(_database.feedback, tableName: 'feedback'),
        'baselines': await _rows(_database.baselines, tableName: 'baselines'),
        'insights': await _rows(_database.insights, tableName: 'insights'),
        'model_meta': await _rows(_database.modelMeta, tableName: 'model_meta'),
        'recurring_series': await _rows(
          _database.recurringSeries,
          tableName: 'recurring_series',
        ),
      },
    };
    _validateArchive(archive);
    return archive;
  }

  Future<List<Map<String, Object?>>> _rows<T extends DataClass>(
    TableInfo<Table, T> table, {
    required String tableName,
  }) async {
    final rows = await (_database.select(table)
          ..limit(_limits.maxRowsPerTable + 1))
        .get();
    return _serializeRows(rows, tableName);
  }

  Future<List<Map<String, Object?>>> _retainedRawSmsRows(DateTime now) async {
    final rows = await (_database.select(_database.rawSms)
          ..where(
            (row) =>
                row.purgeAfter.isNull() | row.purgeAfter.isBiggerThanValue(now),
          )
          ..limit(_limits.maxRowsPerTable + 1))
        .get();
    return _serializeRows(rows, 'raw_sms');
  }

  List<Map<String, Object?>> _serializeRows<T extends DataClass>(
    List<T> rows,
    String tableName,
  ) {
    _assertTableRowCount(rows.length, tableName);
    return rows
        .map((row) => row.toJson())
        .cast<Map<String, Object?>>()
        .toList(growable: false);
  }

  Future<void> _restoreArchive(
    Map<String, Object?> archive, {
    required DateTime now,
  }) async {
    final tables = archive['tables']! as Map<String, Object?>;
    final database = _database;

    await database.transaction(() async {
      await database.delete(database.recurringSeries).go();
      await database.delete(database.modelMeta).go();
      await database.delete(database.insights).go();
      await database.delete(database.baselines).go();
      await database.delete(database.feedback).go();
      await database.delete(database.rules).go();
      await database.delete(database.merchantAliases).go();
      await database.delete(database.transactions).go();
      await database.delete(database.paymentSources).go();
      await database.delete(database.rawSms).go();
      await database.delete(database.merchants).go();
      await database.delete(database.categories).go();

      for (final row in _tableRows(tables, 'categories')) {
        await database.into(database.categories).insert(Category.fromJson(row));
      }
      for (final row in _tableRows(tables, 'merchants')) {
        await database.into(database.merchants).insert(
              Merchant.fromJson({'userLabel': null, ...row}),
            );
      }
      for (final row in _tableRows(tables, 'raw_sms')) {
        final rawSms = RawSm.fromJson(row);
        if (rawSms.failureReason != null &&
            rawSms.failureReason != SmsFailureReason.unparsed &&
            rawSms.failureReason != SmsFailureReason.processingError) {
          throw const EncryptedBackupException(
            'Malformed archive table row: invalid raw SMS failure reason',
          );
        }
        if (!rawSms.purgeAfter.isAfter(now)) {
          continue;
        }
        await database.into(database.rawSms).insert(rawSms);
      }
      for (final row in _tableRows(tables, 'merchant_aliases')) {
        await database
            .into(database.merchantAliases)
            .insert(MerchantAliase.fromJson(row));
      }
      for (final row in _optionalTableRows(tables, 'payment_sources')) {
        await database
            .into(database.paymentSources)
            .insert(PaymentSource.fromJson(row));
      }
      for (final row in _tableRows(tables, 'transactions')) {
        await database.into(database.transactions).insert(
              Transaction.fromJson({
                'paymentSourceId': null,
                'ownedTransferId': null,
                'isAnalyticsExcluded': false,
                ...row,
              }),
            );
      }
      for (final row in _tableRows(tables, 'rules')) {
        await database.into(database.rules).insert(Rule.fromJson(row));
      }
      for (final row in _tableRows(tables, 'feedback')) {
        await database
            .into(database.feedback)
            .insert(FeedbackData.fromJson(row));
      }
      for (final row in _optionalTableRows(tables, 'baselines')) {
        await database.into(database.baselines).insert(Baseline.fromJson(row));
      }
      for (final row in _optionalTableRows(tables, 'insights')) {
        await database.into(database.insights).insert(Insight.fromJson(row));
      }
      for (final row in _optionalTableRows(tables, 'model_meta')) {
        await database
            .into(database.modelMeta)
            .insert(ModelMetaData.fromJson(row));
      }
      for (final row in _optionalTableRows(tables, 'recurring_series')) {
        await database
            .into(database.recurringSeries)
            .insert(RecurringSery.fromJson(row));
      }
    });
  }

  List<Map<String, dynamic>> _tableRows(
    Map<String, Object?> tables,
    String name,
  ) {
    final value = tables[name];
    if (value is! List) {
      throw EncryptedBackupException('Archive missing table $name');
    }
    _assertTableRowCount(value.length, name);
    return value
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _optionalTableRows(
    Map<String, Object?> tables,
    String name,
  ) {
    final value = tables[name];
    if (value == null) return const [];
    if (value is! List) {
      throw EncryptedBackupException('Invalid table $name');
    }
    _assertTableRowCount(value.length, name);
    return value
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  void _validateArchive(Map<String, Object?> archive) {
    final version = archive['version'];
    final rawTables = archive['tables'];
    if ((version != 1 && version != 2 && version != 3) || rawTables is! Map) {
      throw const EncryptedBackupException('Unsupported encrypted export');
    }
    var totalRows = 0;
    for (final entry in rawTables.entries) {
      final value = entry.value;
      if (value is! List) {
        throw EncryptedBackupException('Invalid archive table ${entry.key}');
      }
      _assertTableRowCount(value.length, entry.key.toString());
      totalRows += value.length;
    }
    if (totalRows > _limits.maxRowsTotal) {
      throw const EncryptedBackupException(
        'Encrypted backup exceeds the maximum row count',
      );
    }
  }

  Map<String, Object?> _decodeJsonMap(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      throw const EncryptedBackupException('Invalid encrypted export');
    } on TypeError {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
  }

  Future<Map<String, Object?>> _encrypt(
    List<int> plaintext, {
    required String passphrase,
  }) async {
    _assertKnownKdfProfile(_kdf);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(AesGcm.defaultNonceLength);
    final key = await _deriveKey(passphrase, salt);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    return {
      'version': 1,
      'kdf': {
        'name': 'argon2id',
        'memory': _kdf.memory,
        'parallelism': _kdf.parallelism,
        'iterations': _kdf.iterations,
        'hash_length': _kdf.hashLength,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'aes-256-gcm',
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'ciphertext': base64Encode(box.cipherText),
      },
    };
  }

  Future<List<int>> _decrypt(
    Map<String, Object?> payload, {
    required String passphrase,
  }) async {
    try {
      final kdf = payload['kdf']! as Map<String, Object?>;
      final cipher = payload['cipher']! as Map<String, Object?>;
      if (payload['version'] != 1 ||
          kdf['name'] != 'argon2id' ||
          cipher['name'] != 'aes-256-gcm') {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final memory = _boundedInt(
        kdf['memory'],
        min: _argon2MemoryKiB,
        max: _argon2MemoryKiB,
      );
      final parallelism = _boundedInt(
        kdf['parallelism'],
        min: 1,
        max: _argon2MaxParallelism,
      );
      final iterations = _boundedInt(
        kdf['iterations'],
        min: 1,
        max: _argon2MaxIterations,
      );
      final hashLength = _boundedInt(
        kdf['hash_length'],
        min: _aes256KeyLength,
        max: _aes256KeyLength,
      );
      if (memory != _argon2MemoryKiB ||
          parallelism != _argon2Parallelism ||
          iterations != _argon2Iterations ||
          hashLength != _argon2HashLength) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      if (memory < 8 * parallelism) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final salt = base64Decode(kdf['salt']! as String);
      final nonce = base64Decode(cipher['nonce']! as String);
      final mac = base64Decode(cipher['mac']! as String);
      final ciphertextEncoded = cipher['ciphertext'];
      if (ciphertextEncoded is! String) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final ciphertext = base64Decode(ciphertextEncoded);
      _assertCiphertextSize(ciphertext.length);
      if (salt.length < 16 ||
          salt.length > 64 ||
          nonce.length != AesGcm.defaultNonceLength ||
          mac.length != _aesGcmMacLength) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final payloadKdf = Argon2id(
        memory: memory,
        parallelism: parallelism,
        iterations: iterations,
        hashLength: hashLength,
      );
      final key = await _deriveKey(passphrase, salt, kdf: payloadKdf);
      final box = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(mac),
      );
      return await AesGcm.with256bits().decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const EncryptedBackupException(
        'Wrong passphrase or corrupt export',
      );
    } on FormatException {
      throw const EncryptedBackupException('Invalid encrypted export');
    } on TypeError {
      throw const EncryptedBackupException('Invalid encrypted export');
    } on ArgumentError {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
  }

  Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt, {
    Argon2id? kdf,
  }) {
    return (kdf ?? _kdf).deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  int _boundedInt(Object? value, {required int min, required int max}) {
    if (value is! int || value < min || value > max) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    return value;
  }

  void _assertKnownKdfProfile(Argon2id kdf) {
    if (kdf.memory != _argon2MemoryKiB ||
        kdf.parallelism != _argon2Parallelism ||
        kdf.iterations != _argon2Iterations ||
        kdf.hashLength != _argon2HashLength) {
      throw const EncryptedBackupException('Unsupported backup KDF profile');
    }
  }

  void _assertEncryptedSize(int length) {
    if (length > _limits.maxEncryptedBytes) {
      throw const EncryptedBackupException(
        'Encrypted backup exceeds the maximum file size',
      );
    }
  }

  void _assertCiphertextSize(int length) {
    if (length > _limits.maxCiphertextBytes) {
      throw const EncryptedBackupException(
        'Encrypted backup payload exceeds the maximum size',
      );
    }
  }

  void _assertTableRowCount(int length, String tableName) {
    if (length > _limits.maxRowsPerTable) {
      throw EncryptedBackupException(
        'Encrypted backup table $tableName exceeds the maximum row count',
      );
    }
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}

class _ChunkedBackupWriter {
  _ChunkedBackupWriter({
    required this.writeChunk,
    required this.cipher,
    required this.key,
    required this.headerBytes,
    required this.baseNonce,
    required this.maxPlaintextBytes,
    required this.maxEncryptedBytes,
    required this.cancellation,
    required this.onProgress,
  });

  static const dataRecord = 1;
  static const manifestRecord = 2;

  final Future<void> Function(List<int> bytes) writeChunk;
  final AesGcm cipher;
  final SecretKey key;
  final List<int> headerBytes;
  final List<int> baseNonce;
  final int maxPlaintextBytes;
  final int maxEncryptedBytes;
  final EncryptedBackupCancellation? cancellation;
  final void Function(int encryptedBytes) onProgress;
  final Uint8List _buffer = Uint8List(encryptedBackupChunkSize);

  var _bufferLength = 0;
  var _chunkCount = 0;
  var _plaintextBytes = 0;
  var _ciphertextBytes = 0;
  var _encryptedBytesWritten = 0;
  var processedRows = 0;

  int get encryptedBytesWritten => _encryptedBytesWritten;

  Future<void> writeHeader() async {
    final bytes = BytesBuilder(copy: false)
      ..add(_chunkedBackupMagic)
      ..add([_chunkedBackupVersion])
      ..add(_uint32BytesFor(headerBytes.length))
      ..add(headerBytes);
    await _writeRaw(bytes.takeBytes());
  }

  Future<void> add(List<int> bytes) async {
    _checkCancellationFor(cancellation);
    var offset = 0;
    while (offset < bytes.length) {
      final available = _buffer.length - _bufferLength;
      final copied = min(available, bytes.length - offset);
      _buffer.setRange(
        _bufferLength,
        _bufferLength + copied,
        bytes,
        offset,
      );
      _bufferLength += copied;
      offset += copied;
      if (_bufferLength == _buffer.length) {
        await _flushDataChunk();
      }
    }
  }

  Future<void> finish() async {
    await _flushDataChunk();
    if (_chunkCount == 0) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': _chunkedBackupVersion,
          'chunks': _chunkCount,
          'plaintext_bytes': _plaintextBytes,
          'ciphertext_bytes': _ciphertextBytes,
        }),
      ),
    );
    await _writeEncryptedRecord(
      kind: manifestRecord,
      plaintext: manifest,
      index: _chunkCount,
    );
  }

  Future<void> _flushDataChunk() async {
    if (_bufferLength == 0) return;
    final plaintext = Uint8List.fromList(_buffer.sublist(0, _bufferLength));
    _bufferLength = 0;
    await _writeEncryptedRecord(
      kind: dataRecord,
      plaintext: plaintext,
      index: _chunkCount,
    );
  }

  Future<void> _writeEncryptedRecord({
    required int kind,
    required List<int> plaintext,
    required int index,
  }) async {
    _checkCancellationFor(cancellation);
    if (kind == dataRecord) {
      _plaintextBytes += plaintext.length;
      _ciphertextBytes += plaintext.length;
      if (_plaintextBytes > maxPlaintextBytes) {
        throw const EncryptedBackupException(
          'Encrypted backup payload exceeds the maximum size',
        );
      }
    }
    final box = await cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: _chunkNonceFor(baseNonce, index),
      aad: _chunkAadFor(headerBytes, index, plaintext.length, kind),
    );
    final record = BytesBuilder(copy: false)
      ..add([kind])
      ..add(_uint32BytesFor(plaintext.length))
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    await _writeRaw(record.takeBytes());
    if (kind == dataRecord) _chunkCount++;
  }

  Future<void> _writeRaw(List<int> bytes) async {
    if (_encryptedBytesWritten + bytes.length > maxEncryptedBytes) {
      throw const EncryptedBackupException(
        'Encrypted backup exceeds the maximum file size',
      );
    }
    _encryptedBytesWritten += bytes.length;
    await writeChunk(bytes);
    onProgress(_encryptedBytesWritten);
  }
}

class _ChunkedArchiveRestorer {
  _ChunkedArchiveRestorer({
    required this.database,
    required this.now,
    required this.maxRowsPerTable,
    required this.maxRowsTotal,
    required this.onRows,
  });

  final AppDatabase database;
  final DateTime now;
  final int maxRowsPerTable;
  final int maxRowsTotal;
  final void Function(int processedRows) onRows;
  final _NdjsonLineBuffer _lines = _NdjsonLineBuffer();
  final _tableCounts = <String, int>{};
  var _processedRows = 0;
  var _sawHeader = false;
  var _sawFooter = false;

  int get totalRows => _processedRows;

  Future<void> clearDatabase() async {
    await database.delete(database.recurringSeries).go();
    await database.delete(database.modelMeta).go();
    await database.delete(database.insights).go();
    await database.delete(database.baselines).go();
    await database.delete(database.feedback).go();
    await database.delete(database.rules).go();
    await database.delete(database.merchantAliases).go();
    await database.delete(database.transactions).go();
    await database.delete(database.paymentSources).go();
    await database.delete(database.rawSms).go();
    await database.delete(database.merchants).go();
    await database.delete(database.categories).go();
  }

  Future<void> add(List<int> bytes) async {
    _lines.add(bytes);
    for (final line in _lines.takeLines()) {
      await _processLine(line);
    }
  }

  Future<void> finish() async {
    _lines.close();
    for (final line in _lines.takeLines()) {
      await _processLine(line);
    }
    if (!_sawHeader || !_sawFooter) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
  }

  Future<void> _processLine(String line) async {
    if (line.trim().isEmpty) return;
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    final record = Map<String, Object?>.from(decoded);
    switch (record['kind']) {
      case 'header':
        if (_sawHeader || record['version'] != 3) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        _sawHeader = true;
      case 'row':
        final tableName = record['table'];
        final row = record['row'];
        if (!_sawHeader || _sawFooter || tableName is! String || row is! Map) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        if (!_tableNames.contains(tableName)) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        final tableRows = (_tableCounts[tableName] ?? 0) + 1;
        if (tableRows > maxRowsPerTable) {
          throw EncryptedBackupException(
            'Encrypted backup table $tableName exceeds the maximum row count',
          );
        }
        _processedRows++;
        if (_processedRows > maxRowsTotal) {
          throw const EncryptedBackupException(
            'Encrypted backup exceeds the maximum row count',
          );
        }
        _tableCounts[tableName] = tableRows;
        await _insertRow(tableName, Map<String, dynamic>.from(row));
        onRows(_processedRows);
      case 'footer':
        if (!_sawHeader ||
            _sawFooter ||
            record['version'] != _chunkedBackupVersion) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        final counts = record['tables'];
        if (counts is! Map || record['rows'] != _processedRows) {
          throw const EncryptedBackupException('Invalid encrypted export');
        }
        for (final tableName in _tableNames) {
          if (counts[tableName] != (_tableCounts[tableName] ?? 0)) {
            throw const EncryptedBackupException('Invalid encrypted export');
          }
        }
        _sawFooter = true;
      default:
        throw const EncryptedBackupException('Invalid encrypted export');
    }
  }

  Future<void> _insertRow(String tableName, Map<String, dynamic> row) async {
    switch (tableName) {
      case 'categories':
        await database.into(database.categories).insert(Category.fromJson(row));
      case 'merchants':
        await database.into(database.merchants).insert(
              Merchant.fromJson({'userLabel': null, ...row}),
            );
      case 'raw_sms':
        final rawSms = RawSm.fromJson(row);
        if (rawSms.failureReason != null &&
            rawSms.failureReason != SmsFailureReason.unparsed &&
            rawSms.failureReason != SmsFailureReason.processingError) {
          throw const EncryptedBackupException(
            'Malformed archive table row: invalid raw SMS failure reason',
          );
        }
        if (rawSms.purgeAfter.isAfter(now)) {
          await database.into(database.rawSms).insert(rawSms);
        }
      case 'merchant_aliases':
        await database
            .into(database.merchantAliases)
            .insert(MerchantAliase.fromJson(row));
      case 'payment_sources':
        await database
            .into(database.paymentSources)
            .insert(PaymentSource.fromJson(row));
      case 'transactions':
        await database.into(database.transactions).insert(
              Transaction.fromJson({
                'paymentSourceId': null,
                'ownedTransferId': null,
                'isAnalyticsExcluded': false,
                ...row,
              }),
            );
      case 'rules':
        await database.into(database.rules).insert(Rule.fromJson(row));
      case 'feedback':
        await database
            .into(database.feedback)
            .insert(FeedbackData.fromJson(row));
      case 'baselines':
        await database.into(database.baselines).insert(Baseline.fromJson(row));
      case 'insights':
        await database.into(database.insights).insert(Insight.fromJson(row));
      case 'model_meta':
        await database
            .into(database.modelMeta)
            .insert(ModelMetaData.fromJson(row));
      case 'recurring_series':
        await database
            .into(database.recurringSeries)
            .insert(RecurringSery.fromJson(row));
      default:
        throw const EncryptedBackupException('Invalid encrypted export');
    }
  }

  static const _tableNames = {
    'categories',
    'merchants',
    'raw_sms',
    'merchant_aliases',
    'payment_sources',
    'transactions',
    'rules',
    'feedback',
    'baselines',
    'insights',
    'model_meta',
    'recurring_series',
  };
}

class _NdjsonLineBuffer {
  final _pendingLines = <String>[];
  final _partial = StringBuffer();
  late final ByteConversionSink _sink = utf8.decoder.startChunkedConversion(
    StringConversionSink.withCallback(_consume),
  );

  void add(List<int> bytes) => _sink.add(bytes);

  List<String> takeLines() {
    final lines = List<String>.of(_pendingLines);
    _pendingLines.clear();
    return lines;
  }

  void close() => _sink.close();

  void _consume(String chunk) {
    _partial.write(chunk);
    var value = _partial.toString();
    var newline = value.indexOf('\n');
    while (newline >= 0) {
      _pendingLines.add(value.substring(0, newline));
      value = value.substring(newline + 1);
      newline = value.indexOf('\n');
    }
    _partial.clear();
    _partial.write(value);
  }
}

class _ChunkedBackupReader {
  _ChunkedBackupReader(Stream<List<int>> stream)
      : _iterator = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  var _offset = 0;
  var bytesRead = 0;
  late final Uint8List headerBytes;

  Future<Map<String, Object?>> readHeader() async {
    final magic = await readExact(_chunkedBackupMagic.length);
    for (var i = 0; i < _chunkedBackupMagic.length; i++) {
      if (magic[i] != _chunkedBackupMagic[i]) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
    }
    final version = (await readExact(1))[0];
    if (version != _chunkedBackupVersion) {
      throw const EncryptedBackupException('Unsupported encrypted export');
    }
    final headerLength = _readUint32(await readExact(4));
    if (headerLength <= 0 || headerLength > _chunkedHeaderMaxBytes) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    headerBytes = await readExact(headerLength);
    final decoded = jsonDecode(utf8.decode(headerBytes));
    if (decoded is! Map) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    final header = Map<String, Object?>.from(decoded);
    if (header['format'] != 'paisatrack-chunked-backup' ||
        header['version'] != _chunkedBackupVersion) {
      throw const EncryptedBackupException('Invalid encrypted export');
    }
    return header;
  }

  Future<int?> readOptionalByte() async {
    final result = await _read(1, allowEof: true);
    return result == null ? null : result[0];
  }

  Future<int> readUint32() async => _readUint32(await readExact(4));

  Future<Uint8List> readExact(int length) async {
    final result = await _read(length);
    return result!;
  }

  Future<Uint8List?> _read(int length, {bool allowEof = false}) async {
    final result = Uint8List(length);
    var copied = 0;
    while (copied < length) {
      final available = _buffer.length - _offset;
      if (available > 0) {
        final take = min(available, length - copied);
        result.setRange(copied, copied + take, _buffer, _offset);
        _offset += take;
        copied += take;
        bytesRead += take;
        continue;
      }
      if (!await _iterator.moveNext()) {
        if (copied == 0 && allowEof) return null;
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      _buffer = Uint8List.fromList(_iterator.current);
      _offset = 0;
    }
    return result;
  }

  Future<void> close() => _iterator.cancel();
}

void _checkCancellationFor(EncryptedBackupCancellation? cancellation) {
  if (cancellation?.isCancelled ?? false) {
    throw const EncryptedBackupException('Backup operation cancelled');
  }
}

List<int> _chunkNonceFor(List<int> baseNonce, int index) {
  final nonce = Uint8List.fromList(baseNonce);
  var value = index;
  for (var i = nonce.length - 1; i >= nonce.length - 8; i--) {
    nonce[i] = value & 0xff;
    value >>= 8;
  }
  return nonce;
}

List<int> _chunkAadFor(
  List<int> headerBytes,
  int index,
  int plaintextLength,
  int kind,
) {
  final result = BytesBuilder(copy: false)
    ..add(headerBytes)
    ..add([kind])
    ..add(_uint64BytesFor(index))
    ..add(_uint32BytesFor(plaintextLength));
  return result.takeBytes();
}

List<int> _uint32BytesFor(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

List<int> _uint64BytesFor(int value) {
  final bytes = Uint8List(8);
  var remaining = value;
  for (var i = 7; i >= 0; i--) {
    bytes[i] = remaining & 0xff;
    remaining >>= 8;
  }
  return bytes;
}

int _readUint32(List<int> bytes) =>
    (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

final encryptedBackupServiceProvider =
    FutureProvider<EncryptedBackupService>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return EncryptedBackupService(
    database: database,
  );
});
