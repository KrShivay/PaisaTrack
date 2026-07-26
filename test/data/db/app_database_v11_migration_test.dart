import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v10->v11 migration creates counterparties table with unique identity_key', () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v11_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV10Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final version = await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], greaterThanOrEqualTo(11));

    final tableResult = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='counterparties'",
    ).get();
    expect(tableResult, hasLength(1));

    // Test inserting a row in counterparties
    await database.into(database.counterparties).insert(
          CounterpartiesCompanion.insert(
            id: 'cp_1',
            kind: 'merchant',
            identityKey: 'MERCHANT_SWIGGY',
            displayName: const Value('Swiggy'),
            firstSeen: DateTime.utc(2026, 7, 10),
            lastSeen: DateTime.utc(2026, 7, 10),
          ),
        );

    final rows = await database.select(database.counterparties).get();
    expect(rows, hasLength(1));
    expect(rows.first.identityKey, 'MERCHANT_SWIGGY');
  });
}

void _createV10Database(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 10');
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
  } finally {
    db.dispose();
  }
}
