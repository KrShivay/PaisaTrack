import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../capture/parser_version.dart';

const encryptedBackupFileName = 'paisatrack_export.ptrack';
const encryptedBackupMaxBytes = 32 * 1024 * 1024;
const encryptedBackupMaxCiphertextBytes = 16 * 1024 * 1024;
const encryptedBackupMaxRowsPerTable = 50 * 1000;
const encryptedBackupMaxRowsTotal = 200 * 1000;
const _argon2MemoryKiB = 19456;
const _argon2Parallelism = 1;
const _argon2Iterations = 2;
const _argon2HashLength = 32;
const _argon2MaxParallelism = 4;
const _argon2MaxIterations = 10;
const _aes256KeyLength = 32;
const _aesGcmMacLength = 16;

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
  }) async {
    final bytes = await exportBytes(passphrase: passphrase);
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, encryptedBackupFileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
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
  }) async {
    if (!await file.exists()) {
      throw const EncryptedBackupException('Encrypted export file not found');
    }

    final length = await file.length();
    _assertEncryptedSize(length);
    await importBytes(bytes: await file.readAsBytes(), passphrase: passphrase);
  }

  /// Restores an encrypted archive selected through the system picker.
  Future<void> importBytes({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    if (passphrase.isEmpty) {
      throw const EncryptedBackupException('Passphrase is required');
    }
    _assertEncryptedSize(bytes.length);
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

final encryptedBackupServiceProvider =
    FutureProvider<EncryptedBackupService>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return EncryptedBackupService(
    database: database,
  );
});
