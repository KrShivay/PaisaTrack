import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/capture/parser_version.dart';
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

  test('raw SMS parser metadata round-trips and accepts legacy rows', () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_failed',
            sender: 'VK-HDFCBK',
            body: 'Sensitive body retained only for the retention window',
            receivedAt: DateTime.utc(2026, 7, 16),
            processed: const Value(false),
            parserVersion: const Value(smsParserVersion),
            failureReason: const Value(SmsFailureReason.unparsed),
            purgeAfter: DateTime.utc(2026, 8, 15),
          ),
        );

    final bytes = await service().exportBytes(
      passphrase: 'raw-sms-metadata-passphrase',
    );
    await database.delete(database.rawSms).go();
    await service().importBytes(
      bytes: bytes,
      passphrase: 'raw-sms-metadata-passphrase',
    );

    final restored = (await database.select(database.rawSms).get()).single;
    expect(restored.parserVersion, smsParserVersion);
    expect(restored.failureReason, SmsFailureReason.unparsed);

    final legacy = RawSm.fromJson({
      'id': 'sms_legacy',
      'sender': 'VK-HDFCBK',
      'body': 'Legacy body',
      'receivedAt': DateTime.utc(2026, 7, 16).toIso8601String(),
      'processed': false,
      'purgeAfter': DateTime.utc(2026, 8, 15).toIso8601String(),
    });
    expect(legacy.parserVersion == null, isTrue);
    expect(legacy.failureReason == null, isTrue);
  });

  test('backup restore rejects non-allowlisted raw SMS failure reasons',
      () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_invalid_reason',
            sender: 'VK-HDFCBK',
            body: 'Synthetic test body',
            receivedAt: DateTime.utc(2026, 7, 16),
            failureReason: const Value('private parser detail'),
            purgeAfter: DateTime.utc(2026, 8, 15),
          ),
        );
    final bytes = await service().exportBytes(
      passphrase: 'invalid-reason-passphrase',
    );
    await database.delete(database.rawSms).go();

    await expectLater(
      service().importBytes(
        bytes: bytes,
        passphrase: 'invalid-reason-passphrase',
      ),
      throwsA(isA<EncryptedBackupException>()),
    );
  });

  test('import derives with the bounded KDF parameters stored in the payload',
      () async {
    final before = await database.select(database.categories).get();
    final bytes =
        await service().exportBytes(passphrase: 'payload-kdf-passphrase');
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
    await importer.importBytes(
      bytes: bytes,
      passphrase: 'payload-kdf-passphrase',
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
  });

  test('import rejects unknown KDF and cipher identifiers', () async {
    final original =
        await service().exportBytes(passphrase: 'algorithm-pin-passphrase');

    for (final mutation in <void Function(Map<String, dynamic>)>[
      (payload) => (payload['kdf'] as Map<String, dynamic>)['name'] = 'argon2i',
      (payload) =>
          (payload['cipher'] as Map<String, dynamic>)['name'] = 'aes-128-gcm',
    ]) {
      final payload = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
      mutation(payload);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      await expectLater(
        service().importBytes(
          bytes: bytes,
          passphrase: 'algorithm-pin-passphrase',
        ),
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
    final original =
        await service().exportBytes(passphrase: 'bounded-kdf-passphrase');
    final payload = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    (payload['kdf'] as Map<String, dynamic>)['memory'] = 256 * 1024 + 1;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    await expectLater(
      service().importBytes(
        bytes: bytes,
        passphrase: 'bounded-kdf-passphrase',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Invalid encrypted export',
        ),
      ),
    );
  });

  test(
      'export enforces minimum passphrase length floor of 12 chars while import allows short legacy passphrases',
      () async {
    await expectLater(
      service().exportBytes(passphrase: 'short'),
      throwsA(
        isA<EncryptedBackupException>().having(
          (e) => e.message,
          'message',
          contains('at least 12 characters'),
        ),
      ),
    );

    await expectLater(
      service().importBytes(
        bytes: Uint8List(0),
        passphrase: '',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (e) => e.message,
          'message',
          contains('Passphrase is required'),
        ),
      ),
    );
  });

  test(
      'backup export/import includes baselines, insights, model_meta, and recurring_series',
      () async {
    final now = DateTime.utc(2026, 7, 20);
    await database.into(database.baselines).insert(
          BaselinesCompanion.insert(
            key: 'food_dining:2026-07',
            mean: 5000,
            std: 250,
            n: 10,
            updatedAt: now,
          ),
        );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'insight_1',
            period: '2026-07',
            kind: 'spending_trend',
            payloadJson: '{"title":"Up"}',
          ),
        );
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: 'classifier_version',
            value: 'v1.2.3',
          ),
        );
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm1',
            canonicalName: 'Swiggy',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'series_1',
            merchantId: 'm1',
            label: 'Swiggy',
            expectedAmount: 1500,
            tolerancePct: 0.1,
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: now,
            lastAmount: 1500,
            amountTrend: 'stable',
            occurrences: 3,
            status: 'active',
            kind: 'expense',
          ),
        );

    final bytes = await service().exportBytes(
      passphrase: 'completeness-passphrase-test',
    );

    await database.delete(database.baselines).go();
    await database.delete(database.insights).go();
    await database.delete(database.modelMeta).go();
    await database.delete(database.recurringSeries).go();

    await service().importBytes(
      bytes: bytes,
      passphrase: 'completeness-passphrase-test',
    );

    expect(await database.select(database.baselines).get(), hasLength(1));
    expect(await database.select(database.insights).get(), hasLength(1));
    expect(await database.select(database.modelMeta).get(), hasLength(1));
    expect(await database.select(database.recurringSeries).get(), hasLength(1));
  });
}
