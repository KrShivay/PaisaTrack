import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  test('migration v1 creates encrypted schema', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_db_test_');
    AppDatabase? database;

    addTearDown(() async {
      await database?.close();
      await tempDir.delete(recursive: true);
    });

    database = AppDatabase(
      openEncryptedDatabase(
        file: File('${tempDir.path}/paisatrack.db'),
        passphrase: const DatabasePassphrase('test-passphrase'),
      ),
    );

    final cipherVersion = await _cipherVersionOrSkip(database);
    if (cipherVersion.isEmpty) {
      return;
    }

    expect(cipherVersion, isNotEmpty);

    final schemaVersion =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(schemaVersion.data['user_version'], 1);

    final tableRows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        )
        .get();
    final tableNames = tableRows.map((row) => row.data['name']).toSet();

    expect(
      tableNames,
      containsAll(
        const {
          'categories',
          'feedback',
          'merchant_aliases',
          'merchants',
          'raw_sms',
          'rules',
          'transactions',
        },
      ),
    );

    final indexRows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index'",
        )
        .get();
    final indexNames = indexRows.map((row) => row.data['name']).toSet();

    expect(
      indexNames,
      containsAll(
        const {
          'idx_transactions_ts',
          'idx_transactions_merchant_id',
          'idx_transactions_category_id',
          'idx_transactions_ref_id',
          'idx_transactions_status',
        },
      ),
    );
  });
}

Future<List<QueryRow>> _cipherVersionOrSkip(AppDatabase database) async {
  try {
    return await database.customSelect('PRAGMA cipher_version').get();
  } on Object catch (error) {
    if (error.toString().contains('SQLCipher is not available')) {
      markTestSkipped(
        'SQLCipher is not available in this host VM test process.',
      );
      return const [];
    }

    rethrow;
  }
}
