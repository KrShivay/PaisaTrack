import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_backup_disposition',
            ts: now.millisecondsSinceEpoch,
            amount: 21,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            isNotTransaction: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'synthetic_sms_id',
            transactionId: 'txn_backup_disposition',
            disposition: 'not_transaction',
            createdAt: now,
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
    final restoredTransaction = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_backup_disposition')))
        .getSingle();
    expect(restoredTransaction.isNotTransaction, isTrue);
    final restoredDisposition =
        await database.select(database.smsDispositions).getSingle();
    expect(restoredDisposition.smsId, 'synthetic_sms_id');
  });

  test('legacy and chunked backups preserve bare-dollar source buckets',
      () async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant_bare_dollar',
            canonicalName: 'Dollar service',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_bare_dollar',
            ts: now.millisecondsSinceEpoch,
            amount: 25,
            currencySymbol: const Value(r'$'),
            direction: 'debit',
            channel: 'card',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'rec_bare_dollar',
            merchantId: 'merchant_bare_dollar',
            label: 'Dollar service',
            expectedAmount: 25,
            currencySymbol: const Value(r'$'),
            tolerancePct: 0.05,
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: now,
            lastAmount: 25,
            amountTrend: 'flat',
            occurrences: 3,
            status: 'active',
            kind: 'subscription',
          ),
        );

    const passphrase = 'bare-dollar-backup-passphrase';
    final legacy = await service().exportBytes(passphrase: passphrase);
    final chunked = await service().exportToFile(
      directory: directory,
      passphrase: passphrase,
    );

    for (final format in ['legacy', 'chunked']) {
      await database.delete(database.recurringSeries).go();
      await database.delete(database.transactions).go();
      if (format == 'legacy') {
        await service().importBytes(bytes: legacy, passphrase: passphrase);
      } else {
        await service().importFromFile(file: chunked, passphrase: passphrase);
      }
      final txn = await database.select(database.transactions).getSingle();
      final series =
          await database.select(database.recurringSeries).getSingle();
      expect(txn.currencyCode, isNull);
      expect(txn.currencySymbol, r'$');
      expect(series.currencyCode, isNull);
      expect(series.currencySymbol, r'$');
    }
  });

  test('legacy v3 archive without dispositions defaults marked state to false',
      () async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_old_legacy',
            ts: now.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            isNotTransaction: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'synthetic_old_sms_id',
            transactionId: 'txn_old_legacy',
            disposition: 'not_transaction',
            createdAt: now,
          ),
        );
    const passphrase = 'legacy-optional-table-passphrase';
    final bytes = await service().exportBytes(passphrase: passphrase);
    final oldArchive = await _legacyArchiveWithoutDispositionTable(
      bytes,
      passphrase,
    );

    await service().importBytes(bytes: oldArchive, passphrase: passphrase);

    final restored = await database.select(database.transactions).getSingle();
    expect(restored.isNotTransaction, isFalse);
    expect(await database.select(database.smsDispositions).get(), isEmpty);
  });

  test('chunked v3 archive accepts missing optional table and footer count',
      () async {
    final now = DateTime.utc(2026, 7, 16);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_old_chunked',
            ts: now.millisecondsSinceEpoch,
            amount: 100,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            isNotTransaction: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: 'synthetic_chunked_sms_id',
            transactionId: 'txn_old_chunked',
            disposition: 'not_transaction',
            createdAt: now,
          ),
        );
    const passphrase = 'chunked-optional-table-passphrase';
    final file = await service().exportToFile(
      directory: directory,
      passphrase: passphrase,
    );
    final oldArchive = await _chunkedArchiveWithoutDispositionTable(
      await file.readAsBytes(),
      passphrase,
    );

    await service().importBytes(bytes: oldArchive, passphrase: passphrase);

    final restored = await database.select(database.transactions).getSingle();
    expect(restored.isNotTransaction, isFalse);
    expect(await database.select(database.smsDispositions).get(), isEmpty);
  });

  test('legacy and chunked imports replace linked transaction rows safely',
      () async {
    for (final format in ['legacy', 'chunked']) {
      final parentId = 'txn_parent_$format';
      final duplicateId = 'txn_duplicate_$format';
      final linkId = 'link_$format';
      final counterpartyId = 'counterparty_$format';
      final eventId = 'expected_$format';
      final categoryParentId = 'category_parent_$format';
      final categoryChildId = 'category_child_$format';
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: categoryParentId,
              name: 'Parent $format',
              icon: 'folder',
              isSpending: true,
              sortOrder: 900,
              isUserCreated: true,
            ),
          );
      await database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: categoryChildId,
              name: 'Child $format',
              parentId: Value(categoryParentId),
              icon: 'tag',
              isSpending: true,
              sortOrder: 901,
              isUserCreated: true,
            ),
          );
      await _insertTransaction(database, parentId);
      await _insertTransaction(
        database,
        duplicateId,
        duplicateOfTxnId: parentId,
      );
      await database.into(database.transactionLinks).insert(
            TransactionLinksCompanion.insert(
              id: linkId,
              fromTxnId: duplicateId,
              toTxnId: parentId,
              linkType: 'refunds',
              basis: 'synthetic backup regression',
              createdAt: DateTime.utc(2026, 8, 2).millisecondsSinceEpoch,
            ),
          );
      await database.into(database.counterparties).insert(
            CounterpartiesCompanion.insert(
              id: counterpartyId,
              kind: 'person',
              identityKey: 'synthetic:$format',
              displayName: Value('Backup counterparty $format'),
              firstSeen: DateTime.utc(2026, 8, 1),
              lastSeen: DateTime.utc(2026, 8, 2),
            ),
          );
      await database.into(database.expectedEvents).insert(
            ExpectedEventsCompanion.insert(
              id: eventId,
              source: 'user',
              counterpartyId: Value(counterpartyId),
              label: 'Expected payment $format',
              expectedAmountPaise: 25000,
              expectedDate: DateTime.utc(2026, 8, 20),
              state: 'snoozed',
              confidence: 1,
              dedupKey: 'expected:$format',
            ),
          );

      final passphrase = 'linked-transactions-$format-passphrase';
      if (format == 'legacy') {
        final bytes = await service().exportBytes(passphrase: passphrase);
        await service().importBytes(bytes: bytes, passphrase: passphrase);
      } else {
        final file = await service().exportToFile(
          directory: directory,
          passphrase: passphrase,
        );
        await service().importFromFile(file: file, passphrase: passphrase);
      }

      final restoredRows = await (database.select(database.transactions)
            ..where((row) => row.id.isIn([parentId, duplicateId])))
          .get();
      expect(restoredRows, hasLength(2));
      final restoredCategory = await (database.select(database.categories)
            ..where((category) => category.id.equals(categoryChildId)))
          .getSingle();
      expect(restoredCategory.parentId, categoryParentId);
      expect(
        restoredRows
            .singleWhere((row) => row.id == duplicateId)
            .duplicateOfTxnId,
        parentId,
      );
      final restoredLink = await (database.select(database.transactionLinks)
            ..where((row) => row.id.equals(linkId)))
          .getSingle();
      expect(restoredLink.fromTxnId, duplicateId);
      expect(restoredLink.toTxnId, parentId);
      final restoredCounterparty =
          await (database.select(database.counterparties)
                ..where((row) => row.id.equals(counterpartyId)))
              .getSingle();
      expect(restoredCounterparty.displayName, 'Backup counterparty $format');
      final restoredEvent = await (database.select(database.expectedEvents)
            ..where((row) => row.id.equals(eventId)))
          .getSingle();
      expect(restoredEvent.counterpartyId, counterpartyId);
      expect(restoredEvent.state, 'snoozed');
      expect(restoredEvent.label, 'Expected payment $format');
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    }
  });

  test('legacy v3 archives without transaction links remain compatible',
      () async {
    const passphrase = 'old-archive-compatibility-passphrase';
    await _insertTransaction(database, 'txn_old_archive');
    await database.into(database.counterparties).insert(
          CounterpartiesCompanion.insert(
            id: 'counterparty_old_archive',
            kind: 'person',
            identityKey: 'old:archive',
            firstSeen: DateTime.utc(2026, 8, 1),
            lastSeen: DateTime.utc(2026, 8, 2),
          ),
        );
    await database.into(database.expectedEvents).insert(
          ExpectedEventsCompanion.insert(
            id: 'expected_old_archive',
            source: 'user',
            label: 'Old pending payment',
            expectedAmountPaise: 10000,
            expectedDate: DateTime.utc(2026, 8, 20),
            state: 'expected',
            confidence: 1,
            dedupKey: 'old:archive',
          ),
        );
    await database.into(database.financialEvents).insert(
          FinancialEventsCompanion.insert(
            id: 'financial_event_old_archive',
            eventKey: 'old:archive',
            keyBasis: 'synthetic',
            kind: 'purchase',
            netAmountPaise: 10000,
            openedAt: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          ),
        );
    await database.into(database.shadowTransactions).insert(
          ShadowTransactionsCompanion.insert(
            id: 'shadow_old_archive',
            sourceId: 'synthetic-source',
            pipelineVersion: 'test-v1',
            outcome: 'accepted',
            observedAt: DateTime.utc(2026, 8, 1),
            updatedAt: DateTime.utc(2026, 8, 2),
          ),
        );
    final currentArchive = await service().exportBytes(
      passphrase: passphrase,
    );
    final oldArchive = await _rewriteLegacyArchive(
      currentArchive,
      passphrase: passphrase,
      rewrite: (archive) {
        (archive['tables'] as Map<String, dynamic>).remove('transaction_links');
        final tables = archive['tables'] as Map<String, dynamic>;
        tables.remove('counterparties');
        tables.remove('expected_events');
      },
    );
    await database.into(database.featureFlags).insert(
          FeatureFlagsCompanion.insert(
            key: 'device_local_flag',
            value: 'true',
          ),
        );

    await service().importBytes(bytes: oldArchive, passphrase: passphrase);

    expect(
      (await database.select(database.transactions).get()).map((row) => row.id),
      contains('txn_old_archive'),
    );
    expect(await database.select(database.transactionLinks).get(), isEmpty);
    expect(await database.select(database.counterparties).get(), isEmpty);
    expect(await database.select(database.expectedEvents).get(), isEmpty);
    expect(await database.select(database.financialEvents).get(), isEmpty);
    expect(await database.select(database.shadowTransactions).get(), isEmpty);
    expect(
      (await database.select(database.featureFlags).getSingle()).value,
      'true',
    );
  });

  test('older chunked v3 archives may omit optional tables', () async {
    const passphrase = 'old-chunked-archive-compatibility-passphrase';
    await _insertTransaction(database, 'txn_old_chunked_archive');
    await _insertTransaction(database, 'txn_old_chunked_related');
    await database.into(database.counterparties).insert(
          CounterpartiesCompanion.insert(
            id: 'counterparty_old_chunked',
            kind: 'person',
            identityKey: 'old:chunked',
            firstSeen: DateTime.utc(2026, 8, 1),
            lastSeen: DateTime.utc(2026, 8, 2),
          ),
        );
    await database.into(database.expectedEvents).insert(
          ExpectedEventsCompanion.insert(
            id: 'expected_old_chunked',
            source: 'user',
            label: 'Old chunked payment',
            expectedAmountPaise: 10000,
            expectedDate: DateTime.utc(2026, 8, 20),
            state: 'expected',
            confidence: 1,
            dedupKey: 'old:chunked',
          ),
        );
    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: 'link_old_chunked',
            fromTxnId: 'txn_old_chunked_related',
            toTxnId: 'txn_old_chunked_archive',
            linkType: 'echo',
            basis: 'synthetic old-format regression',
            createdAt: DateTime.utc(2026, 8, 2).millisecondsSinceEpoch,
          ),
        );
    final currentFile = await service().exportToFile(
      directory: directory,
      passphrase: passphrase,
    );
    final oldArchive = await _removeChunkedOptionalTables(
      await currentFile.readAsBytes(),
      passphrase: passphrase,
    );
    final oldFile = File('${directory.path}/old-v3-chunked.ptrack');
    await oldFile.writeAsBytes(oldArchive);

    await service().importFromFile(file: oldFile, passphrase: passphrase);

    expect(
      (await database.select(database.transactions).get()).map((row) => row.id),
      contains('txn_old_chunked_archive'),
    );
    expect(await database.select(database.transactionLinks).get(), isEmpty);
    expect(await database.select(database.counterparties).get(), isEmpty);
    expect(await database.select(database.expectedEvents).get(), isEmpty);
  });

  test('failed linked restore rolls back and retains the existing ledger',
      () async {
    const passphrase = 'rollback-linked-import-passphrase';
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'category_rollback_parent',
            name: 'Rollback parent',
            icon: 'folder',
            isSpending: true,
            sortOrder: 990,
            isUserCreated: true,
          ),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'category_rollback_child',
            name: 'Rollback child',
            parentId: const Value('category_rollback_parent'),
            icon: 'tag',
            isSpending: true,
            sortOrder: 991,
            isUserCreated: true,
          ),
        );
    await _insertTransaction(database, 'txn_rollback_parent');
    await _insertTransaction(
      database,
      'txn_rollback_child',
      duplicateOfTxnId: 'txn_rollback_parent',
    );
    await database.into(database.transactionLinks).insert(
          TransactionLinksCompanion.insert(
            id: 'link_rollback',
            fromTxnId: 'txn_rollback_child',
            toTxnId: 'txn_rollback_parent',
            linkType: 'refunds',
            basis: 'synthetic rollback regression',
            createdAt: DateTime.utc(2026, 8, 2).millisecondsSinceEpoch,
          ),
        );
    await database.into(database.counterparties).insert(
          CounterpartiesCompanion.insert(
            id: 'counterparty_rollback',
            kind: 'person',
            identityKey: 'rollback:person',
            displayName: const Value('Keep after rollback'),
            firstSeen: DateTime.utc(2026, 8, 1),
            lastSeen: DateTime.utc(2026, 8, 2),
          ),
        );
    await database.into(database.expectedEvents).insert(
          ExpectedEventsCompanion.insert(
            id: 'expected_rollback',
            source: 'user',
            counterpartyId: const Value('counterparty_rollback'),
            label: 'Keep after rollback',
            expectedAmountPaise: 12000,
            expectedDate: DateTime.utc(2026, 8, 20),
            state: 'snoozed',
            confidence: 1,
            dedupKey: 'rollback:payment',
          ),
        );
    final originalCategories = await database.select(database.categories).get();
    final originalTransactions =
        await database.select(database.transactions).get();
    final originalLinks =
        await database.select(database.transactionLinks).get();
    final originalCounterparties =
        await database.select(database.counterparties).get();
    final originalEvents = await database.select(database.expectedEvents).get();

    Future<void> expectDatabaseUnchanged() async {
      expect(
        (await database.select(database.categories).get())
            .map((row) => row.toJson()),
        originalCategories.map((row) => row.toJson()),
      );
      expect(
        (await database.select(database.transactions).get())
            .map((row) => row.toJson()),
        originalTransactions.map((row) => row.toJson()),
      );
      expect(
        (await database.select(database.transactionLinks).get())
            .map((row) => row.toJson()),
        originalLinks.map((row) => row.toJson()),
      );
      expect(
        (await database.select(database.counterparties).get())
            .map((row) => row.toJson()),
        originalCounterparties.map((row) => row.toJson()),
      );
      expect(
        (await database.select(database.expectedEvents).get())
            .map((row) => row.toJson()),
        originalEvents.map((row) => row.toJson()),
      );
    }

    final malformedRows = [
      (
        table: 'transaction_links',
        id: 'link_rollback',
        field: 'toTxnId',
        value: 'missing_transaction'
      ),
      (
        table: 'categories',
        id: 'category_rollback_child',
        field: 'parentId',
        value: 42
      ),
      (
        table: 'transactions',
        id: 'txn_rollback_child',
        field: 'duplicateOfTxnId',
        value: 42
      ),
    ];
    for (final format in ['legacy', 'chunked']) {
      for (final malformed in malformedRows) {
        Uint8List invalidArchive;
        if (format == 'legacy') {
          final archive = await service().exportBytes(passphrase: passphrase);
          invalidArchive = await _rewriteLegacyArchive(
            archive,
            passphrase: passphrase,
            rewrite: (archive) {
              final rows = (archive['tables']
                  as Map<String, dynamic>)[malformed.table] as List<dynamic>;
              (rows.singleWhere(
                (row) => (row as Map<String, dynamic>)['id'] == malformed.id,
              ) as Map<String, dynamic>)[malformed.field] = malformed.value;
            },
          );
          await expectLater(
            service().importBytes(
              bytes: invalidArchive,
              passphrase: passphrase,
            ),
            throwsA(isA<Exception>()),
          );
        } else {
          final archiveFile = await service().exportToFile(
            directory: directory,
            passphrase: passphrase,
          );
          invalidArchive = await _rewriteChunkedArchive(
            await archiveFile.readAsBytes(),
            passphrase: passphrase,
            rewriteRecords: (records) {
              final record = records.singleWhere(
                (record) =>
                    record['kind'] == 'row' &&
                    record['table'] == malformed.table &&
                    (record['row'] as Map<String, dynamic>)['id'] ==
                        malformed.id,
              );
              (record['row'] as Map<String, dynamic>)[malformed.field] =
                  malformed.value;
              return records;
            },
          );
          final invalidFile = File('${directory.path}/invalid-$format.ptrack');
          await invalidFile.writeAsBytes(invalidArchive);
          await expectLater(
            service().importFromFile(
              file: invalidFile,
              passphrase: passphrase,
            ),
            throwsA(isA<Exception>()),
          );
        }
        await expectDatabaseUnchanged();
      }
    }
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

  test('restore detaches transactions from expired raw SMS in both formats',
      () async {
    for (final format in ['legacy', 'chunked']) {
      final smsId = 'sms_expired_$format';
      final transactionId = 'txn_expired_$format';
      await database.into(database.rawSms).insert(
            RawSmsCompanion.insert(
              id: smsId,
              sender: 'VK-HDFCBK',
              body: 'Expired synthetic SMS',
              receivedAt: DateTime.utc(2026, 7, 1),
              purgeAfter: DateTime.utc(2026, 8, 2),
            ),
          );
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: transactionId,
              ts: DateTime.utc(2026, 7, 1).millisecondsSinceEpoch,
              amount: 20,
              direction: 'debit',
              channel: 'upi',
              parseSource: 'template',
              smsId: Value(smsId),
              confidenceJson: '{}',
              status: 'auto',
              createdAt: DateTime.utc(2026, 7, 1),
              updatedAt: DateTime.utc(2026, 7, 1),
            ),
          );

      final passphrase = 'expired-sms-$format-passphrase';
      final backup = format == 'legacy'
          ? await service().exportBytes(passphrase: passphrase)
          : await service().exportToFile(
              directory: directory,
              passphrase: passphrase,
            );
      await database.delete(database.transactions).go();
      await database.delete(database.rawSms).go();

      if (format == 'legacy') {
        await service().importBytes(
          bytes: backup as Uint8List,
          passphrase: passphrase,
        );
      } else {
        await service().importFromFile(
          file: backup as File,
          passphrase: passphrase,
        );
      }

      final restored = await (database.select(database.transactions)
            ..where((row) => row.id.equals(transactionId)))
          .getSingle();
      expect(restored.id, transactionId);
      expect(restored.smsId, isNull);
      expect(await database.select(database.rawSms).get(), isEmpty);
    }
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

Future<void> _insertTransaction(
  AppDatabase database,
  String id, {
  String? duplicateOfTxnId,
}) async {
  final timestamp = DateTime.utc(2026, 8, 2);
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: timestamp.millisecondsSinceEpoch,
          amount: 125,
          direction: 'debit',
          channel: 'upi',
          parseSource: 'template',
          duplicateOfTxnId: Value(duplicateOfTxnId),
          confidenceJson: '{}',
          status: 'auto',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
}

Future<Uint8List> _rewriteLegacyArchive(
  Uint8List bytes, {
  required String passphrase,
  required void Function(Map<String, dynamic> archive) rewrite,
}) async {
  final envelope =
      Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  final oldKdf = Map<String, dynamic>.from(envelope['kdf'] as Map);
  final oldCipher = Map<String, dynamic>.from(envelope['cipher'] as Map);
  final algorithm = Argon2id(
    memory: oldKdf['memory'] as int,
    parallelism: oldKdf['parallelism'] as int,
    iterations: oldKdf['iterations'] as int,
    hashLength: oldKdf['hash_length'] as int,
  );
  final cipher = AesGcm.with256bits();
  final oldKey = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: base64Decode(oldKdf['salt'] as String),
  );
  final plaintext = await cipher.decrypt(
    SecretBox(
      base64Decode(oldCipher['ciphertext'] as String),
      nonce: base64Decode(oldCipher['nonce'] as String),
      mac: Mac(base64Decode(oldCipher['mac'] as String)),
    ),
    secretKey: oldKey,
  );
  final archive =
      Map<String, dynamic>.from(jsonDecode(utf8.decode(plaintext)) as Map);
  rewrite(archive);

  final random = Random.secure();
  final salt = List<int>.generate(16, (_) => random.nextInt(256));
  final nonce = List<int>.generate(
    AesGcm.defaultNonceLength,
    (_) => random.nextInt(256),
  );
  final newKey = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final box = await cipher.encrypt(
    utf8.encode(jsonEncode(archive)),
    secretKey: newKey,
    nonce: nonce,
  );
  envelope['kdf'] = {...oldKdf, 'salt': base64Encode(salt)};
  envelope['cipher'] = {
    ...oldCipher,
    'nonce': base64Encode(box.nonce),
    'mac': base64Encode(box.mac.bytes),
    'ciphertext': base64Encode(box.cipherText),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

Future<Uint8List> _removeChunkedOptionalTables(
  Uint8List bytes, {
  required String passphrase,
}) async {
  return _rewriteChunkedArchive(
    bytes,
    passphrase: passphrase,
    rewriteRecords: (records) {
      const optionalTables = {
        'counterparties',
        'expected_events',
        'transaction_links',
      };
      final removedRowCount = records
          .where(
            (record) =>
                record['kind'] == 'row' &&
                optionalTables.contains(record['table']),
          )
          .length;
      records.removeWhere(
        (record) =>
            record['kind'] == 'row' && optionalTables.contains(record['table']),
      );
      for (final record in records.where(
        (record) => record['kind'] == 'footer',
      )) {
        final tables = Map<String, dynamic>.from(record['tables'] as Map)
          ..removeWhere((table, _) => optionalTables.contains(table));
        record['tables'] = tables;
        record['rows'] = (record['rows'] as int) - removedRowCount;
      }
      return records;
    },
  );
}

Future<Uint8List> _rewriteChunkedArchive(
  Uint8List bytes, {
  required String passphrase,
  required List<Map<String, dynamic>> Function(
    List<Map<String, dynamic>> records,
  ) rewriteRecords,
}) async {
  final headerLength = _readUint32(bytes, 5);
  final originalHeaderBytes = bytes.sublist(9, 9 + headerLength);
  final header = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(originalHeaderBytes)) as Map,
  );
  final kdfFields = Map<String, dynamic>.from(header['kdf'] as Map);
  final algorithm = Argon2id(
    memory: kdfFields['memory'] as int,
    parallelism: kdfFields['parallelism'] as int,
    iterations: kdfFields['iterations'] as int,
    hashLength: kdfFields['hash_length'] as int,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: base64Decode(kdfFields['salt'] as String),
  );
  final cipher = AesGcm.with256bits();
  final baseNonce = base64Decode(header['base_nonce'] as String);
  final data = BytesBuilder(copy: false);
  var chunkIndex = 0;
  var offset = 9 + headerLength;
  while (offset < bytes.length) {
    final kind = bytes[offset];
    final length = _readUint32(bytes, offset + 1);
    final ciphertext = bytes.sublist(offset + 5, offset + 5 + length);
    final mac = bytes.sublist(offset + 5 + length, offset + 5 + length + 16);
    final plaintext = await cipher.decrypt(
      SecretBox(
        ciphertext,
        nonce: _chunkNonceForTest(baseNonce, chunkIndex),
        mac: Mac(mac),
      ),
      secretKey: key,
      aad: _chunkAadForTest(
        originalHeaderBytes,
        chunkIndex,
        length,
        kind,
      ),
    );
    offset += 1 + 4 + length + 16;
    if (kind == 1) {
      data.add(plaintext);
      chunkIndex++;
    } else if (kind == 2) {
      break;
    } else {
      throw StateError('Unexpected chunked record kind');
    }
  }

  final records = utf8
      .decode(data.takeBytes())
      .split('\n')
      .where((line) => line.isNotEmpty)
      .map((line) => Map<String, dynamic>.from(jsonDecode(line) as Map))
      .toList();
  final rewrittenRecords = rewriteRecords(records);
  final rewrittenLines = <String>[];
  for (final record in rewrittenRecords) {
    rewrittenLines.add(jsonEncode(record));
  }
  final rewrittenData = utf8.encode('${rewrittenLines.join('\n')}\n');
  final random = Random.secure();
  final newBaseNonce = List<int>.generate(
    AesGcm.defaultNonceLength,
    (_) => random.nextInt(256),
  );
  header['base_nonce'] = base64Encode(newBaseNonce);
  final headerBytes = utf8.encode(jsonEncode(header));
  final output = BytesBuilder(copy: false)
    ..add([0x50, 0x54, 0x52, 0x4b, 2])
    ..add(_testUint32Bytes(headerBytes.length))
    ..add(headerBytes);

  Future<void> writeRecord(int kind, List<int> plaintext, int index) async {
    final box = await cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: _chunkNonceForTest(newBaseNonce, index),
      aad: _chunkAadForTest(headerBytes, index, plaintext.length, kind),
    );
    output
      ..add([kind])
      ..add(_testUint32Bytes(plaintext.length))
      ..add(box.cipherText)
      ..add(box.mac.bytes);
  }

  var newChunkCount = 0;
  for (var start = 0; start < rewrittenData.length; start += 60 * 1024) {
    final end = min(start + 60 * 1024, rewrittenData.length);
    await writeRecord(1, rewrittenData.sublist(start, end), newChunkCount);
    newChunkCount++;
  }
  final manifest = utf8.encode(
    jsonEncode({
      'version': 2,
      'chunks': newChunkCount,
      'plaintext_bytes': rewrittenData.length,
      'ciphertext_bytes': rewrittenData.length,
    }),
  );
  await writeRecord(2, manifest, newChunkCount);
  return Uint8List.fromList(output.takeBytes());
}

List<int> _chunkNonceForTest(List<int> baseNonce, int index) {
  final nonce = Uint8List.fromList(baseNonce);
  var value = index;
  for (var i = nonce.length - 1; i >= nonce.length - 8; i--) {
    nonce[i] = value & 0xff;
    value >>= 8;
  }
  return nonce;
}

List<int> _chunkAadForTest(
  List<int> headerBytes,
  int index,
  int length,
  int kind,
) =>
    [
      ...headerBytes,
      kind,
      ..._testUint64Bytes(index),
      ..._testUint32Bytes(length),
    ];

List<int> _testUint32Bytes(int value) => [
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ];

List<int> _testUint64Bytes(int value) {
  final bytes = Uint8List(8);
  var remaining = value;
  for (var i = 7; i >= 0; i--) {
    bytes[i] = remaining & 0xff;
    remaining >>= 8;
  }
  return bytes;
}

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _recordLength(List<int> bytes, int offset) =>
    1 + 4 + _readUint32(bytes, offset + 1) + 16;

Future<Uint8List> _legacyArchiveWithoutDispositionTable(
  Uint8List encrypted,
  String passphrase,
) async {
  final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
  final kdf = envelope['kdf'] as Map<String, dynamic>;
  final cipher = envelope['cipher'] as Map<String, dynamic>;
  final salt = base64Decode(kdf['salt'] as String);
  final key = await Argon2id(
    memory: kdf['memory'] as int,
    parallelism: kdf['parallelism'] as int,
    iterations: kdf['iterations'] as int,
    hashLength: kdf['hash_length'] as int,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(passphrase)),
    nonce: salt,
  );
  final aes = AesGcm.with256bits();
  final plaintext = await aes.decrypt(
    SecretBox(
      base64Decode(cipher['ciphertext'] as String),
      nonce: base64Decode(cipher['nonce'] as String),
      mac: Mac(base64Decode(cipher['mac'] as String)),
    ),
    secretKey: key,
  );
  final archive = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  final tables = archive['tables'] as Map<String, dynamic>;
  tables.remove('sms_dispositions');
  for (final row in (tables['transactions'] as List<dynamic>)) {
    (row as Map<String, dynamic>).remove('isNotTransaction');
  }

  final nonce = List<int>.generate(12, (index) => index + 1);
  final box = await aes.encrypt(
    utf8.encode(jsonEncode(archive)),
    secretKey: key,
    nonce: nonce,
  );
  envelope['cipher'] = {
    'name': 'aes-256-gcm',
    'nonce': base64Encode(box.nonce),
    'mac': base64Encode(box.mac.bytes),
    'ciphertext': base64Encode(box.cipherText),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

Future<Uint8List> _chunkedArchiveWithoutDispositionTable(
  Uint8List encrypted,
  String passphrase,
) async {
  final headerLength = _readUint32(encrypted, 5);
  final originalHeaderBytes = encrypted.sublist(9, 9 + headerLength);
  final header =
      jsonDecode(utf8.decode(originalHeaderBytes)) as Map<String, dynamic>;
  final kdf = header['kdf'] as Map<String, dynamic>;
  final salt = base64Decode(kdf['salt'] as String);
  final key = await Argon2id(
    memory: kdf['memory'] as int,
    parallelism: kdf['parallelism'] as int,
    iterations: kdf['iterations'] as int,
    hashLength: kdf['hash_length'] as int,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  final aes = AesGcm.with256bits();
  final originalBaseNonce = base64Decode(header['base_nonce'] as String);
  final plaintext = BytesBuilder(copy: false);
  var offset = 9 + headerLength;
  var originalIndex = 0;
  while (offset < encrypted.length) {
    final kind = encrypted[offset++];
    final length = _readUint32(encrypted, offset);
    offset += 4;
    final ciphertext = encrypted.sublist(offset, offset + length);
    offset += length;
    final mac = encrypted.sublist(offset, offset + 16);
    offset += 16;
    if (kind == 2) break;
    plaintext.add(
      await aes.decrypt(
        SecretBox(
          ciphertext,
          nonce: _chunkNonceForTest(originalBaseNonce, originalIndex),
          mac: Mac(mac),
        ),
        secretKey: key,
        aad: _chunkAadForTest(
          originalHeaderBytes,
          originalIndex,
          length,
          kind,
        ),
      ),
    );
    originalIndex++;
  }

  var removed = 0;
  final records = utf8
      .decode(plaintext.takeBytes())
      .split('\n')
      .where((line) => line.isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .where((record) {
    if (record['kind'] == 'row' && record['table'] == 'sms_dispositions') {
      removed++;
      return false;
    }
    if (record['kind'] == 'row' && record['table'] == 'transactions') {
      (record['row'] as Map<String, dynamic>).remove('isNotTransaction');
    }
    if (record['kind'] == 'footer') {
      (record['tables'] as Map<String, dynamic>).remove('sms_dispositions');
      record['rows'] = (record['rows'] as int) - removed;
    }
    return true;
  }).toList(growable: false);
  if (removed == 0) throw StateError('Fixture did not contain a disposition');
  final archiveBytes = utf8.encode('${records.map(jsonEncode).join('\n')}\n');

  final newBaseNonce = List<int>.generate(12, (index) => 100 + index);
  header['base_nonce'] = base64Encode(newBaseNonce);
  final headerBytes = utf8.encode(jsonEncode(header));
  final chunkSize = header['chunk_size'] as int;
  final output = BytesBuilder(copy: false)
    ..add(const [0x50, 0x54, 0x52, 0x4b])
    ..add([header['version'] as int])
    ..add(_testUint32Bytes(headerBytes.length))
    ..add(headerBytes);
  var chunkCount = 0;
  for (var start = 0; start < archiveBytes.length; start += chunkSize) {
    final end = min(start + chunkSize, archiveBytes.length);
    final chunk = archiveBytes.sublist(start, end);
    final box = await aes.encrypt(
      chunk,
      secretKey: key,
      nonce: _chunkNonceForTest(newBaseNonce, chunkCount),
      aad: _chunkAadForTest(headerBytes, chunkCount, chunk.length, 1),
    );
    output
      ..add([1])
      ..add(_testUint32Bytes(chunk.length))
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    chunkCount++;
  }
  final manifest = utf8.encode(
    jsonEncode({
      'version': header['version'],
      'chunks': chunkCount,
      'plaintext_bytes': archiveBytes.length,
      'ciphertext_bytes': archiveBytes.length,
    }),
  );
  final manifestBox = await aes.encrypt(
    manifest,
    secretKey: key,
    nonce: _chunkNonceForTest(newBaseNonce, chunkCount),
    aad: _chunkAadForTest(headerBytes, chunkCount, manifest.length, 2),
  );
  output
    ..add([2])
    ..add(_testUint32Bytes(manifest.length))
    ..add(manifestBox.cipherText)
    ..add(manifestBox.mac.bytes);
  return output.takeBytes();
}

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
