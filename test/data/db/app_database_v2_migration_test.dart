import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Verifies the v1->v2 migration (ADR 0003, T-036): new nullable columns are
/// added without data loss, and the echo-suppression backfill converts
/// `is_deleted=1` rows to `duplicate_of_txn_id` links where a unique match
/// exists, leaving unmatched suppressed rows untouched.
void main() {
  test('v1->v2 migration adds columns and backfills duplicate links', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v2_migration_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));

    _createV1Database(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    // Triggers the lazy migration on first use.
    final rows = await (database.select(database.transactions)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    final schemaVersion =
        await database.customSelect('PRAGMA user_version').getSingle();
    // Opening a v1 file applies every additive migration through the current
    // schema, while the assertions below continue to prove the v1->v2 step.
    expect(schemaVersion.data['user_version'], 3);

    final columns =
        await database.customSelect("PRAGMA table_info('transactions')").get();
    final columnNames = columns.map((r) => r.data['name']).toSet();
    expect(
      columnNames,
      containsAll(['counterparty_vpa', 'duplicate_of_txn_id']),
    );

    final indexRows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    expect(
      indexRows.map((r) => r.data['name']),
      contains('idx_transactions_duplicate_of_txn_id'),
    );

    // Original rows preserved.
    expect(rows, hasLength(3));

    final primary = rows.firstWhere((r) => r.id == 'txn_bank');
    final echo = rows.firstWhere((r) => r.id == 'txn_wallet_echo');
    final orphan = rows.firstWhere((r) => r.id == 'txn_orphan_echo');

    // The paired echo converts to a link and is un-suppressed.
    expect(echo.duplicateOfTxnId, primary.id);
    expect(echo.isDeleted, isFalse);

    // No unique match in this v1 database: stays conservatively suppressed.
    expect(orphan.duplicateOfTxnId, isNull);
    expect(orphan.isDeleted, isTrue);

    // counterparty_vpa is not backfilled — new column, no reconstruction.
    expect(primary.counterpartyVpa, isNull);
  });
}

/// Hand-builds a v1 `transactions` table (pre-ADR-0003 shape: no
/// `counterparty_vpa`/`duplicate_of_txn_id`) with `user_version=1`, seeding a
/// suppressed cross-source echo pair plus one suppressed row with no match.
void _createV1Database(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 1');
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
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    final baseTs = DateTime.utc(2026, 7, 1, 10, 30).millisecondsSinceEpoch;
    void insert({
      required String id,
      required int ts,
      required double amount,
      String direction = 'debit',
      String? merchantRaw,
      String? refId,
      bool isDeleted = false,
    }) {
      db.execute(
        '''
        INSERT INTO transactions
          (id, ts, amount, direction, channel, merchant_raw, ref_id,
           parse_source, confidence_json, status, is_deleted, created_at,
           updated_at)
        VALUES (?, ?, ?, ?, 'upi', ?, ?, 'template', '{}', 'auto', ?, ?, ?)
        ''',
        [
          id,
          ts,
          amount,
          direction,
          merchantRaw,
          refId,
          isDeleted ? 1 : 0,
          ts,
          ts,
        ],
      );
    }

    insert(id: 'txn_bank', ts: baseTs, amount: 449, merchantRaw: 'amazon@ybl');
    insert(
      id: 'txn_wallet_echo',
      ts: baseTs + const Duration(minutes: 4).inMilliseconds,
      amount: 449,
      merchantRaw: 'Amazon Pay India',
      isDeleted: true,
    );
    insert(
      id: 'txn_orphan_echo',
      ts: baseTs + const Duration(minutes: 20).inMilliseconds,
      amount: 999,
      merchantRaw: 'Unrelated Merchant',
      isDeleted: true,
    );
  } finally {
    db.dispose();
  }
}
