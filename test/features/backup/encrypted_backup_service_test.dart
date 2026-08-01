import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/capture/parser_version.dart';
import 'package:paisatrack/core/platform/system_document_gateway.dart';
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
      clock: () => DateTime.utc(2026, 8, 2),
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

    expect(
      utf8.decode(await file.readAsBytes(), allowMalformed: true),
      isNot(contains(before.first.name)),
    );

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

  test('chunked file export reports monotonic progress and finalizes',
      () async {
    final progress = <EncryptedBackupProgress>[];
    final file = await service().exportToFile(
      directory: directory,
      passphrase: 'chunked-progress-passphrase',
      onProgress: progress.add,
    );
    final bytes = await file.readAsBytes();

    expect(bytes.sublist(0, 4), [0x50, 0x54, 0x52, 0x4b]);
    expect(bytes[4], 2);
    expect(
      progress.map((event) => event.phase),
      contains(
        EncryptedBackupProgressPhase.encrypting,
      ),
    );
    expect(progress.last.phase, EncryptedBackupProgressPhase.completed);
    expect(progress.last.processedRows, progress.last.totalRows);
    expect(
      progress.map((event) => event.processedBytes).toList(),
      orderedEquals(
        progress.map((event) => event.processedBytes).toList()..sort(),
      ),
    );
  });

  test('chunked envelope rejects tampering, reordering, and truncation',
      () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_large_chunked',
            sender: 'VK-HDFCBK',
            body: 'Sensitive body ' * 10000,
            receivedAt: DateTime.utc(2026, 7, 16),
            purgeAfter: DateTime.utc(2026, 8, 15),
          ),
        );
    final file = await service().exportToFile(
      directory: directory,
      passphrase: 'chunked-integrity-passphrase',
    );
    final original = await file.readAsBytes();
    final headerLength = _readUint32(original, 5);
    final recordStarts = <int>[];
    var offset = 9 + headerLength;
    while (offset < original.length) {
      recordStarts.add(offset);
      final length = _readUint32(original, offset + 1);
      offset += 1 + 4 + length + 16;
    }
    expect(recordStarts.length, greaterThanOrEqualTo(3));

    final tampered = Uint8List.fromList(original);
    tampered[recordStarts.first + 5] ^= 0x01;
    final reordered = Uint8List.fromList(original);
    final first = _recordLength(reordered, recordStarts[0]);
    final second = _recordLength(reordered, recordStarts[1]);
    final firstRecord =
        reordered.sublist(recordStarts[0], recordStarts[0] + first);
    final secondRecord =
        reordered.sublist(recordStarts[1], recordStarts[1] + second);
    reordered.setRange(recordStarts[0], recordStarts[0] + second, secondRecord);
    reordered.setRange(
      recordStarts[0] + second,
      recordStarts[0] + second + first,
      firstRecord,
    );
    final truncated =
        Uint8List.fromList(original.sublist(0, original.length - 1));
    final unsupported = Uint8List.fromList(original)..[4] = 9;

    for (final bytes in [tampered, reordered, truncated, unsupported]) {
      await expectLater(
        service().importBytes(
          bytes: bytes,
          passphrase: 'chunked-integrity-passphrase',
        ),
        throwsA(isA<EncryptedBackupException>()),
      );
    }
  });

  test('chunked export cancellation removes the partial destination', () async {
    final cancellation = EncryptedBackupCancellation()..cancel();
    final file = File('${directory.path}/cancelled.ptrack');

    await expectLater(
      service().exportToFile(
        directory: directory,
        passphrase: 'chunked-cancellation-passphrase',
        cancellation: cancellation,
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Backup operation cancelled',
        ),
      ),
    );
    expect(await file.exists(), isFalse);
  });

  test('document export/import uses bounded gateway sessions', () async {
    final gateway = _MemoryDocumentGateway();
    final exported = await service().exportToDocument(
      gateway: gateway,
      suggestedName: 'paisatrack_backup.ptrack',
      mimeType: 'application/octet-stream',
      passphrase: 'document-session-passphrase',
    );
    expect(exported, isTrue);
    expect(gateway.maxWrittenChunk, lessThanOrEqualTo(maxDocumentChunkBytes));

    await database.delete(database.categories).go();
    final imported = await service().importFromDocument(
      gateway: gateway,
      mimeType: 'application/octet-stream',
      passphrase: 'document-session-passphrase',
    );
    expect(imported, isTrue);
    expect(await database.select(database.categories).get(), isNotEmpty);
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

  test('archive round-trips a raw SMS row without parser metadata', () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_legacy_archive',
            sender: 'VK-HDFCBK',
            body: 'Legacy body',
            receivedAt: DateTime.utc(2026, 7, 16),
            purgeAfter: DateTime.utc(2026, 8, 15),
          ),
        );

    final bytes = await service().exportBytes(
      passphrase: 'legacy-archive-passphrase',
    );
    await database.delete(database.rawSms).go();
    await service().importBytes(
      bytes: bytes,
      passphrase: 'legacy-archive-passphrase',
    );

    final restored = (await database.select(database.rawSms).get()).single;
    expect(restored.id, 'sms_legacy_archive');
    expect(restored.parserVersion, isNull);
    expect(restored.failureReason, isNull);
  });

  test('export excludes expired raw SMS while retaining active rows', () async {
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_active',
            sender: 'VK-HDFCBK',
            body: 'Active body',
            receivedAt: DateTime.utc(2026, 7, 16),
            purgeAfter: DateTime.utc(2026, 8, 3),
          ),
        );
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_expired',
            sender: 'VK-HDFCBK',
            body: 'Expired body',
            receivedAt: DateTime.utc(2026, 7, 1),
            purgeAfter: DateTime.utc(2026, 8, 2),
          ),
        );

    final bytes = await service().exportBytes(
      passphrase: 'retention-boundary-passphrase',
    );
    await database.delete(database.rawSms).go();
    await service().importBytes(
      bytes: bytes,
      passphrase: 'retention-boundary-passphrase',
    );

    final restored = await database.select(database.rawSms).get();
    expect(restored.map((row) => row.id), ['sms_active']);
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
    expect(kdf['memory'], 19456);
    expect(kdf['iterations'], 2);

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
      (payload) => (payload['kdf'] as Map<String, dynamic>)['memory'] = 32768,
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

  test('export rejects an unsupported configured KDF profile', () async {
    final unsupported = EncryptedBackupService(
      database: database,
      random: Random(9),
      clock: () => DateTime.utc(2026, 8, 2),
      kdf: Argon2id(
        memory: 32768,
        parallelism: 1,
        iterations: 2,
        hashLength: 32,
      ),
    );

    await expectLater(
      unsupported.exportBytes(passphrase: 'unsupported-kdf-passphrase'),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Unsupported backup KDF profile',
        ),
      ),
    );
  });

  test('rejects oversized files and ciphertext before restoring', () async {
    final file = await service().exportToFile(
      directory: directory,
      passphrase: 'size-boundary-passphrase',
    );
    final bytes = await file.readAsBytes();
    final limited = EncryptedBackupService(
      database: database,
      random: Random(10),
      clock: () => DateTime.utc(2026, 8, 2),
      limits: const EncryptedBackupLimits(
        maxEncryptedBytes: 1,
        maxCiphertextBytes: 1,
      ),
    );

    final expected = throwsA(
      isA<EncryptedBackupException>().having(
        (error) => error.message,
        'message',
        'Encrypted backup exceeds the maximum file size',
      ),
    );
    await expectLater(
      limited.importFromFile(
        file: file,
        passphrase: 'size-boundary-passphrase',
      ),
      expected,
    );
    await expectLater(
      limited.importBytes(
        bytes: bytes,
        passphrase: 'size-boundary-passphrase',
      ),
      expected,
    );

    final ciphertextLimited = EncryptedBackupService(
      database: database,
      random: Random(11),
      clock: () => DateTime.utc(2026, 8, 2),
      limits: const EncryptedBackupLimits(maxCiphertextBytes: 1),
    );
    await expectLater(
      ciphertextLimited.importBytes(
        bytes: bytes,
        passphrase: 'size-boundary-passphrase',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Encrypted backup payload exceeds the maximum size',
        ),
      ),
    );
  });

  test('rejects malformed JSON before restoring', () async {
    final before = await database.select(database.categories).get();

    await expectLater(
      service().importBytes(
        bytes: Uint8List.fromList(utf8.encode('[]')),
        passphrase: 'malformed-json-passphrase',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Invalid encrypted export',
        ),
      ),
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
  });

  test('enforces per-table and total archive row limits before restore',
      () async {
    final bytes = await service().exportBytes(
      passphrase: 'row-boundary-passphrase',
    );
    final before = await database.select(database.categories).get();

    final tableLimited = EncryptedBackupService(
      database: database,
      random: Random(12),
      clock: () => DateTime.utc(2026, 8, 2),
      limits: const EncryptedBackupLimits(maxRowsPerTable: 1),
    );
    await expectLater(
      tableLimited.importBytes(
        bytes: bytes,
        passphrase: 'row-boundary-passphrase',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          contains('table categories exceeds'),
        ),
      ),
    );

    final totalLimited = EncryptedBackupService(
      database: database,
      random: Random(13),
      clock: () => DateTime.utc(2026, 8, 2),
      limits: const EncryptedBackupLimits(maxRowsTotal: 1),
    );
    await expectLater(
      totalLimited.importBytes(
        bytes: bytes,
        passphrase: 'row-boundary-passphrase',
      ),
      throwsA(
        isA<EncryptedBackupException>().having(
          (error) => error.message,
          'message',
          'Encrypted backup exceeds the maximum row count',
        ),
      ),
    );

    final after = await database.select(database.categories).get();
    expect(after.map((row) => row.toJson()), before.map((row) => row.toJson()));
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

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _recordLength(List<int> bytes, int offset) =>
    1 + 4 + _readUint32(bytes, offset + 1) + 16;

class _MemoryDocumentGateway extends SystemDocumentGateway {
  _MemoryDocumentGateway() : super();

  final _written = <int>[];
  var _readOffset = 0;
  var maxWrittenChunk = 0;

  Uint8List get _source => Uint8List.fromList(_written);

  @override
  Future<String?> beginSaveDocument({
    required String suggestedName,
    required String mimeType,
  }) async {
    _written.clear();
    return 'save';
  }

  @override
  Future<bool> writeDocumentChunk({
    required String sessionId,
    required Uint8List bytes,
  }) async {
    maxWrittenChunk = max(maxWrittenChunk, bytes.length);
    _written.addAll(bytes);
    return true;
  }

  @override
  Future<bool> finishDocument({required String sessionId}) async => true;

  @override
  Future<void> cancelDocument({required String sessionId}) async {}

  @override
  Future<String?> beginOpenDocument({required String mimeType}) async {
    _readOffset = 0;
    return 'open';
  }

  @override
  Future<Uint8List?> readDocumentChunk({
    required String sessionId,
    int maxBytes = maxDocumentChunkBytes,
  }) async {
    final source = _source;
    if (_readOffset >= source.length) return null;
    final end = min(_readOffset + maxBytes, source.length);
    final result = source.sublist(_readOffset, end);
    _readOffset = end;
    return result;
  }

  @override
  Future<void> closeDocument({required String sessionId}) async {}
}
