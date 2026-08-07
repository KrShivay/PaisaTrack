import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v15->v16 migration creates the shadow transactions table', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v16_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    final legacy = sqlite3.open(dbPath);
    legacy.execute('PRAGMA user_version = 15');
    legacy.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        channel TEXT NOT NULL,
        account_hint TEXT,
        payment_source_id TEXT,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0
      )
    ''');
    legacy.execute('''
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
    legacy.dispose();

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 16);
    final columns = await database
        .customSelect('PRAGMA table_info(shadow_transactions)')
        .get();
    expect(
      columns.map((row) => row.data['name']),
      containsAll([
        'id',
        'source_id',
        'pipeline_version',
        'outcome',
        'amount_paise',
        'direction',
        'merchant_key',
        'category_id',
        'observed_at',
        'updated_at',
      ]),
    );
  });
}
