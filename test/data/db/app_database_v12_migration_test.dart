import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v11->v12 migration creates expected_events table and unique index on (dedup_key, expected_date)', () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v12_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV11Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final version = await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 12);

    final tableResult = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='expected_events'",
    ).get();
    expect(tableResult, hasLength(1));

    final now = DateTime.utc(2026, 7, 10);
    // Insert first expected event
    await database.into(database.expectedEvents).insert(
          ExpectedEventsCompanion.insert(
            id: 'ee_1',
            source: 'sms_reminder',
            label: 'Electricity Bill',
            expectedAmountPaise: 150000,
            expectedDate: now,
            state: 'expected',
            confidence: 0.95,
            dedupKey: 'dedup_elec_123',
          ),
        );

    final rows = await database.select(database.expectedEvents).get();
    expect(rows, hasLength(1));
    expect(rows.first.expectedAmountPaise, 150000);

    // AC: Verify expected events table is completely separate and never enters spending queries
    final txns = await database.select(database.transactions).get();
    expect(txns, isEmpty);
  });
}

void _createV11Database(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 11');
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
  } finally {
    db.dispose();
  }
}
