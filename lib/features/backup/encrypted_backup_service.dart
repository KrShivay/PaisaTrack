import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

const encryptedBackupFileName = 'paisatrack_export.ptrack';
const _argon2MinMemoryKiB = 8;
const _argon2MaxMemoryKiB = 256 * 1024;
const _argon2MaxParallelism = 4;
const _argon2MaxIterations = 10;
const _aes256KeyLength = 32;
const _aesGcmMacLength = 16;

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
  })  : _database = database,
        _random = random ?? Random.secure(),
        _kdf = kdf ??
            Argon2id(
              memory: 19456,
              parallelism: 1,
              iterations: 2,
              hashLength: 32,
            ),
        _cipher = cipher ?? AesGcm.with256bits();

  final AppDatabase _database;
  final Random _random;
  final Argon2id _kdf;
  final AesGcm _cipher;

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
    if (passphrase.length < 12) {
      throw const EncryptedBackupException(
        'Passphrase must be at least 12 characters long',
      );
    }
    final archive = await _readArchive();
    final payload = await _encrypt(
      utf8.encode(jsonEncode(archive)),
      passphrase: passphrase,
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  Future<void> importFromFile({
    required File file,
    required String passphrase,
  }) async {
    if (!await file.exists()) {
      throw const EncryptedBackupException('Encrypted export file not found');
    }

    await importBytes(
      bytes: await file.readAsBytes(),
      passphrase: passphrase,
    );
  }

  /// Restores an encrypted archive selected through the system picker.
  Future<void> importBytes({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    if (passphrase.length < 12) {
      throw const EncryptedBackupException(
        'Passphrase must be at least 12 characters long',
      );
    }
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final plaintext = await _decrypt(payload, passphrase: passphrase);
    final archive = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    _validateArchive(archive);

    await _restoreArchive(archive);
  }

  Future<Map<String, Object?>> _readArchive() async {
    return {
      'version': 2,
      'tables': {
        'categories': await _rows(_database.categories),
        'merchants': await _rows(_database.merchants),
        'raw_sms': await _rows(_database.rawSms),
        'merchant_aliases': await _rows(_database.merchantAliases),
        'payment_sources': await _rows(_database.paymentSources),
        'transactions': await _rows(_database.transactions),
        'rules': await _rows(_database.rules),
        'feedback': await _rows(_database.feedback),
        'baselines': await _rows(_database.baselines),
        'insights': await _rows(_database.insights),
        'model_meta': await _rows(_database.modelMeta),
        'recurring_series': await _rows(_database.recurringSeries),
      },
    };
  }

  Future<List<Map<String, Object?>>> _rows<T extends DataClass>(
    TableInfo<Table, T> table,
  ) async {
    final rows = await _database.select(table).get();
    return rows
        .map((row) => row.toJson())
        .cast<Map<String, Object?>>()
        .toList(growable: false);
  }

  Future<void> _restoreArchive(Map<String, Object?> archive) async {
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
        await database.into(database.rawSms).insert(RawSm.fromJson(row));
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
    return value
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  void _validateArchive(Map<String, Object?> archive) {
    final version = archive['version'];
    if ((version != 1 && version != 2) ||
        archive['tables'] is! Map<String, Object?>) {
      throw const EncryptedBackupException('Unsupported encrypted export');
    }
  }

  Future<Map<String, Object?>> _encrypt(
    List<int> plaintext, {
    required String passphrase,
  }) async {
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
        min: _argon2MinMemoryKiB,
        max: _argon2MaxMemoryKiB,
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
      if (memory < 8 * parallelism) {
        throw const EncryptedBackupException('Invalid encrypted export');
      }
      final salt = base64Decode(kdf['salt']! as String);
      final nonce = base64Decode(cipher['nonce']! as String);
      final mac = base64Decode(cipher['mac']! as String);
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
        base64Decode(cipher['ciphertext']! as String),
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
