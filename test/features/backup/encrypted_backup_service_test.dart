import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/backup/encrypted_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory directory;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    directory = await Directory.systemTemp.createTemp('backup_test_');
    await database.seedDefaultCategories();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  EncryptedBackupService service() {
    return EncryptedBackupService(
      database: database,
      random: Random(7),
      kdf: Argon2id(
        memory: 8,
        parallelism: 1,
        iterations: 1,
        hashLength: 32,
      ),
    );
  }

  test('export import round-trips domain rows without plaintext temp files',
      () async {
    final before = await database.select(database.categories).get();
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.paymentSources).insert(
          PaymentSourcesCompanion.insert(
            id: 'source_card',
            kind: 'card',
            maskedIdentifier: 'xx4242',
            nickname: const Value('Daily card'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final file = await service().exportToFile(
      directory: directory,
      passphrase: 'correct horse battery staple',
    );

    expect(await file.readAsString(), isNot(contains(before.first.name)));

    await database.delete(database.categories).go();
    await service().importFromFile(
      file: file,
      passphrase: 'correct horse battery staple',
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
    final restoredSource =
        await database.select(database.paymentSources).getSingle();
    expect(restoredSource.nickname, 'Daily card');
  });

  test('wrong passphrase fails closed and leaves current data untouched',
      () async {
    final file = await service().exportToFile(
      directory: directory,
      passphrase: 'right-passphrase',
    );
    final before = await database.select(database.categories).get();

    await expectLater(
      service().importFromFile(file: file, passphrase: 'wrong-passphrase'),
      throwsA(isA<EncryptedBackupException>()),
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
  });

  test('in-memory export import round-trips for document picker', () async {
    final before = await database.select(database.categories).get();
    final bytes = await service().exportBytes(passphrase: 'picker-passphrase');

    expect(String.fromCharCodes(bytes), isNot(contains(before.first.name)));
    await database.delete(database.categories).go();
    await service().importBytes(
      bytes: bytes,
      passphrase: 'picker-passphrase',
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
  });

  test('import derives with the bounded KDF parameters stored in the payload',
      () async {
    final before = await database.select(database.categories).get();
    final bytes = await service().exportBytes(passphrase: 'payload-kdf');
    final payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final kdf = payload['kdf'] as Map<String, dynamic>;
    expect(kdf['memory'], 8);
    expect(kdf['iterations'], 1);

    await database.delete(database.categories).go();
    final importer = EncryptedBackupService(
      database: database,
      random: Random(8),
      kdf: Argon2id(
        memory: 32,
        parallelism: 1,
        iterations: 2,
        hashLength: 32,
      ),
    );
    await importer.importBytes(bytes: bytes, passphrase: 'payload-kdf');

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
  });

  test('import rejects unknown KDF and cipher identifiers', () async {
    final original = await service().exportBytes(passphrase: 'algorithm-pin');

    for (final mutation in <void Function(Map<String, dynamic>)>[
      (payload) => (payload['kdf'] as Map<String, dynamic>)['name'] = 'argon2i',
      (payload) =>
          (payload['cipher'] as Map<String, dynamic>)['name'] = 'aes-128-gcm',
    ]) {
      final payload = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
      mutation(payload);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      await expectLater(
        service().importBytes(bytes: bytes, passphrase: 'algorithm-pin'),
        throwsA(
          isA<EncryptedBackupException>().having(
            (error) => error.message,
            'message',
            'Invalid encrypted export',
          ),
        ),
      );
    }
  });

  test('import rejects excessive Argon2 parameters before key derivation',
      () async {
    final original = await service().exportBytes(passphrase: 'bounded-kdf');
    final payload = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    (payload['kdf'] as Map<String, dynamic>)['memory'] = 256 * 1024 + 1;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    await expectLater(
      service().importBytes(bytes: bytes, passphrase: 'bounded-kdf'),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Invalid encrypted export',
        ),
      ),
    );
  });
}
