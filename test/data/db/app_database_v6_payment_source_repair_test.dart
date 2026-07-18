import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Regression coverage for the S0/S1 device blocker: a v5 `payment_sources`
/// table whose rows carried NULLs in non-null-typed columns and datetimes
/// written in milliseconds. The generated row mapper force-unwraps those
/// columns, so a single bad row crashed the transactions and accounts screens
/// with `Null check operator used on a null value`.
///
/// The v6 repair must make every row readable again without clearing app data.
void main() {
  test('v5->v6 repairs null and millisecond payment_sources rows', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v6_repair_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV5DatabaseWithCorruptSource(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    // Reading the table is exactly what crashed on device: it exercises the
    // generated force-unwrapping mapper. It must now succeed.
    final sources = await database.select(database.paymentSources).get();
    expect(sources, hasLength(2));

    final repaired = {for (final row in sources) row.id: row};

    final nulled = repaired['source_xx1234_upi']!;
    expect(nulled.isActive, isTrue);
    expect(nulled.includeInAnalytics, isTrue);
    expect(nulled.isOwned, isTrue);
    // A NULL created_at was backfilled to a real, recent timestamp.
    expect(nulled.createdAt.year, greaterThanOrEqualTo(2020));

    // The millisecond timestamp was rescaled to seconds, so it maps to a
    // sane date rather than a year far in the future.
    final msRow = repaired['source_xx9999_card']!;
    expect(msRow.createdAt.year, lessThan(2100));
    expect(msRow.createdAt.year, greaterThanOrEqualTo(2020));

    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    // The old millisecond-writing trigger was dropped and the corrected one
    // recreated by beforeOpen.
    final triggers = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'trigger' "
          "AND name = 'trg_transactions_payment_source'",
        )
        .getSingle();
    expect(triggers.data['sql'], isNot(contains('* 1000')));
  });
}

/// Hand-builds a v5 database whose `payment_sources` rows are shaped like the
/// ones the shipped v5 migration/trigger could produce: one with NULLs in
/// non-null-typed columns and one with millisecond datetimes.
void _createV5DatabaseWithCorruptSource(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 5');
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
        payment_source_id TEXT,
        owned_transfer_id TEXT,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    // Non-null-typed columns are declared without NOT NULL here to reproduce an
    // early-iteration table shape that allowed NULLs to be stored.
    db.execute('''
      CREATE TABLE payment_sources (
        id TEXT NOT NULL PRIMARY KEY,
        kind TEXT NOT NULL,
        masked_identifier TEXT NOT NULL,
        nickname TEXT,
        institution TEXT,
        is_active INTEGER,
        include_in_analytics INTEGER,
        is_owned INTEGER,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    // Row 1: NULLs in is_active/include_in_analytics/is_owned/created_at.
    db.execute('''
      INSERT INTO payment_sources
        (id, kind, masked_identifier, is_active, include_in_analytics,
         is_owned, created_at, updated_at)
      VALUES ('source_xx1234_upi', 'upi', 'xx1234', NULL, NULL, NULL, NULL, NULL)
    ''');
    // Row 2: millisecond datetimes, as the old trigger/backfill wrote them.
    db.execute('''
      INSERT INTO payment_sources
        (id, kind, masked_identifier, is_active, include_in_analytics,
         is_owned, created_at, updated_at)
      VALUES ('source_xx9999_card', 'card', 'xx9999', 1, 1, 1,
              1782864000000, 1782864000000)
    ''');
    // The old millisecond-writing trigger, present on an upgraded device.
    db.execute('''
      CREATE TRIGGER trg_transactions_payment_source
      AFTER INSERT ON transactions
      WHEN NEW.payment_source_id IS NULL
      BEGIN
        INSERT OR IGNORE INTO payment_sources
          (id, kind, masked_identifier, include_in_analytics, is_owned,
           created_at, updated_at)
        VALUES (NEW.id, 'upi', 'xx', 1, 1,
                CAST(unixepoch() * 1000 AS INTEGER),
                CAST(unixepoch() * 1000 AS INTEGER));
      END
    ''');
  } finally {
    db.dispose();
  }
}
