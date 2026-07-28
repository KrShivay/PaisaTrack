import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v12->v13 migration creates feature_flags table with key primary key', () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v13_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV12Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final version = await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], greaterThanOrEqualTo(13));

    final tableResult = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='feature_flags'",
    ).get();
    expect(tableResult, hasLength(1));

    // Insert a feature flag row and verify readback
    await database.into(database.featureFlags).insert(
          FeatureFlagsCompanion.insert(
            key: 'test_flag',
            value: 'true',
          ),
        );

    final rows = await database.select(database.featureFlags).get();
    expect(rows, hasLength(1));
    expect(rows.first.key, 'test_flag');
    expect(rows.first.value, 'true');
  });
}

void _createV12Database(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 12');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        ts INTEGER NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        channel TEXT NOT NULL,
        parse_source TEXT NOT NULL,
        confidence_json TEXT NOT NULL,
        status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE counterparties (
        id TEXT NOT NULL PRIMARY KEY,
        kind TEXT NOT NULL,
        identity_key TEXT NOT NULL UNIQUE,
        display_name TEXT,
        inferred_name TEXT,
        psp_family TEXT,
        merchant_id TEXT,
        first_seen INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        txn_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    db.execute('''
      CREATE TABLE financial_events (
        id TEXT NOT NULL PRIMARY KEY,
        event_key TEXT NOT NULL UNIQUE,
        key_basis TEXT NOT NULL,
        kind TEXT NOT NULL,
        net_amount_paise INTEGER NOT NULL,
        currency TEXT NOT NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        state TEXT NOT NULL,
        confidence REAL NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE transaction_links (
        id TEXT NOT NULL PRIMARY KEY,
        from_txn_id TEXT NOT NULL,
        to_txn_id TEXT NOT NULL,
        link_type TEXT NOT NULL,
        confidence REAL NOT NULL,
        basis TEXT NOT NULL,
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE expected_events (
        id TEXT NOT NULL PRIMARY KEY,
        source TEXT NOT NULL,
        label TEXT NOT NULL,
        expected_amount_paise INTEGER NOT NULL,
        expected_date INTEGER NOT NULL,
        state TEXT NOT NULL,
        confidence REAL NOT NULL,
        dedup_key TEXT NOT NULL
      )
    ''');
  } finally {
    db.dispose();
  }
}
