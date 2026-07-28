import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v8->v9 migration adds lifecycle_state, lifecycle_reason, and message_kind columns and backfills to settled', () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v9_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV8DatabaseWithExistingTransaction(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final txn = await (database.select(database.transactions)..where((t) => t.id.equals('txn_v8_legacy'))).getSingle();
    expect(txn.lifecycleState, 'settled');
    expect(txn.lifecycleReason, isNull);
    expect(txn.messageKind, isNull);

    final version = await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], greaterThanOrEqualTo(9));

    final indexResult = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_transactions_lifecycle_state'",
    ).get();
    expect(indexResult, isNotEmpty);
  });
}

void _createV8DatabaseWithExistingTransaction(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 8');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        ts INTEGER NOT NULL,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        channel TEXT NOT NULL,
        account_hint TEXT,
        payment_source_id TEXT,
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
        owned_transfer_id TEXT,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0,
        evidence_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      INSERT INTO transactions (
        id, ts, amount, direction, channel, parse_source, confidence_json, status, created_at, updated_at
      ) VALUES (
        'txn_v8_legacy', 1751702400000, 250.0, 'debit', 'upi', 'template', '{"parser":{"c":1.0,"src":"template"}}', 'confirmed', 1751702400, 1751702400
      )
    ''');
  } finally {
    db.dispose();
  }
}
