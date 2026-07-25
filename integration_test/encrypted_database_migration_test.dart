import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keystore passphrase is stable until app storage is cleared', (
    tester,
  ) async {
    final provider = AndroidKeystoreDatabasePassphraseProvider();

    await provider.debugResetForTests();
    final first = await provider.getPassphrase();
    final second = await provider.getPassphrase();

    expect(first.value, isNotEmpty);
    expect(second.value, first.value);

    await provider.debugResetForTests();
    final freshInstall = await provider.getPassphrase();

    expect(freshInstall.value, isNotEmpty);
    expect(freshInstall.value, isNot(first.value));

    await provider.debugResetForTests();
  });

  testWidgets('migration v1 creates encrypted schema', (tester) async {
    final provider = AndroidKeystoreDatabasePassphraseProvider();
    final tempDir = await getTemporaryDirectory();
    final dbFile = File('${tempDir.path}/paisatrack_integration_test.db');
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }

    final passphrase = await provider.getPassphrase();
    final database = AppDatabase(
      openEncryptedDatabase(
        file: dbFile,
        passphrase: passphrase,
      ),
    );

    addTearDown(() async {
      await database.close();
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
    });

    final cipherVersion =
        await database.customSelect('PRAGMA cipher_version').get();
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
  });
}
