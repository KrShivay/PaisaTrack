import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Verifies T-048's additive v2->v3 analytics-schema migration.
void main() {
  test('v2->v3 migration creates analytics tables without losing rows',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v3_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV2Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final transactions = await database.select(database.transactions).get();
    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final indexes = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();

    expect(version.data['user_version'], 3);
    expect(transactions, hasLength(1));
    expect(transactions.single.id, 'v2-row');
    expect(
      tables.map((row) => row.data['name']),
      containsAll(['recurring_series', 'baselines', 'model_meta', 'insights']),
    );
    expect(
      indexes.map((row) => row.data['name']),
      containsAll([
        'idx_insights_period',
        'idx_recurring_series_merchant_id',
        'idx_recurring_series_next_expected_date',
      ]),
    );
  });
}

/// Hand-builds the v2 shape so migration coverage is independent of v3 Drift
/// definitions. The existing transaction is the no-data-loss assertion.
void _createV2Database(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 2');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        ts INTEGER NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        channel TEXT NOT NULL,
        account_hint TEXT,
        merchant_raw TEXT,
        merchant_id TEXT,
        category_id TEXT,
        description TEXT,
        balance_after REAL,
        ref_id TEXT,
        parse_source TEXT NOT NULL,
        sms_id TEXT,
        confidence_json TEXT NOT NULL,
        status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        counterparty_vpa TEXT,
        duplicate_of_txn_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      INSERT INTO transactions
        (id, ts, amount, direction, channel, parse_source, confidence_json,
         status, created_at, updated_at)
      VALUES ('v2-row', 1782864000000, 42.0, 'debit', 'upi', 'template', '{}',
              'confirmed', 1782864000000, 1782864000000)
    ''');
  } finally {
    db.dispose();
  }
}
