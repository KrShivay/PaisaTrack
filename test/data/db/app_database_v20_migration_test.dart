import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v19 databases gain recurring intent and supporting SMS links',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v20_');
    final path = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));

    final previous = AppDatabase(NativeDatabase(File(path)));
    await previous.into(previous.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_1',
            ts: 1767225600000,
            amount: 1234.56,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    await previous.close();

    // Rebuild the exact v19 shape: no column, no table.
    final raw = sqlite3.open(path);
    raw.execute('DROP INDEX idx_sms_transaction_links_transaction_id');
    raw.execute('DROP TABLE sms_transaction_links');
    raw.execute('ALTER TABLE transactions DROP COLUMN recurring_override');
    raw.execute('PRAGMA user_version = 19');
    raw.dispose();

    final migrated = AppDatabase(NativeDatabase(File(path)));
    addTearDown(migrated.close);

    final version =
        await migrated.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 20);

    final row = await migrated.select(migrated.transactions).getSingle();
    expect(row.id, 'txn_1');
    expect(row.amount, 1234.56);
    expect(row.recurringOverride, isNull);

    await (migrated.update(migrated.transactions)
          ..where((t) => t.id.equals('txn_1')))
        .write(
      const TransactionsCompanion(
        recurringOverride: Value('not_recurring'),
      ),
    );
    expect(
      (await migrated.select(migrated.transactions).getSingle())
          .recurringOverride,
      'not_recurring',
    );

    await migrated.into(migrated.smsTransactionLinks).insert(
          SmsTransactionLinksCompanion.insert(
            smsId: 'sms_9',
            transactionId: 'txn_1',
            kind: 'emi_notice',
            basis: 'amount_account_window',
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        );
    final link =
        await migrated.select(migrated.smsTransactionLinks).getSingle();
    expect(link.confidence, 1.0);
    expect(link.kind, 'emi_notice');

    final indexes = await migrated
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'sms_transaction_links'")
        .get();
    expect(
      indexes.map((r) => r.data['name']),
      contains('idx_sms_transaction_links_transaction_id'),
    );
  });

  test('v20 step is idempotent when the shapes already exist', () async {
    final tempDir = await Directory.systemTemp.createTemp('paisatrack_v20b_');
    final path = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));

    final fresh = AppDatabase(NativeDatabase(File(path)));
    await fresh.customSelect('SELECT 1').get();
    await fresh.close();

    final raw = sqlite3.open(path);
    raw.execute('PRAGMA user_version = 19');
    raw.dispose();

    final migrated = AppDatabase(NativeDatabase(File(path)));
    addTearDown(migrated.close);
    final version =
        await migrated.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 20);
  });
}
