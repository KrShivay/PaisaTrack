import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v13->v14 migration adds nullable raw SMS attempt metadata', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v14_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV13Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 15);
    final payeeEvidence =
        await database.customSelect('PRAGMA table_info(payee_evidence)').get();
    expect(
      payeeEvidence.map((row) => row.data['name']),
      containsAll([
        'transaction_id',
        'evidence_type',
        'normalized_key',
        'display_value',
      ]),
    );
    final columns =
        await database.customSelect('PRAGMA table_info(raw_sms)').get();
    expect(
      columns.map((row) => row.data['name']),
      containsAll(['parser_version', 'failure_reason']),
    );

    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_legacy',
            sender: 'VK-HDFCBK',
            body: 'Spent Rs 449',
            receivedAt: DateTime.utc(2026, 7, 5),
            purgeAfter: DateTime.utc(2026, 8, 4),
          ),
        );
    final row = (await database.select(database.rawSms).get()).single;
    expect(row.parserVersion, isNull);
    expect(row.failureReason, isNull);
  });

  test('v13->v14 creates raw SMS table for legacy databases without it',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v14_legacy_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV13Database(dbPath, includeRawSms: false);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final tables =
        await database.customSelect('PRAGMA table_info(raw_sms)').get();
    expect(
      tables.map((row) => row.data['name']),
      containsAll([
        'id',
        'parser_version',
        'failure_reason',
        'purge_after',
      ]),
    );
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: 'sms_created_on_upgrade',
            sender: 'VK-HDFCBK',
            body: 'Spent Rs 449',
            receivedAt: DateTime.utc(2026, 7, 5),
            purgeAfter: DateTime.utc(2026, 8, 4),
          ),
        );
    expect(await database.select(database.rawSms).get(), hasLength(1));
  });
}

void _createV13Database(String path, {bool includeRawSms = true}) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 13');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        channel TEXT NOT NULL,
        account_hint TEXT,
        payment_source_id TEXT,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0
      )
    ''');
    db.execute('''
      CREATE TABLE payment_sources (
        id TEXT NOT NULL PRIMARY KEY,
        kind TEXT NOT NULL,
        masked_identifier TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        include_in_analytics INTEGER NOT NULL DEFAULT 1,
        is_owned INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    if (includeRawSms) {
      db.execute('''
        CREATE TABLE raw_sms (
          id TEXT NOT NULL PRIMARY KEY,
          sender TEXT NOT NULL,
          body TEXT NOT NULL,
          received_at INTEGER NOT NULL,
          processed INTEGER NOT NULL DEFAULT 0,
          purge_after INTEGER NOT NULL
        )
      ''');
    }
  } finally {
    db.dispose();
  }
}
