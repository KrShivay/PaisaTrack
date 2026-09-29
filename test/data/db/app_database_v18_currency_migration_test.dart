import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v17 rows migrate with unknown source currency', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v18_currency_');
    final path = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));

    final previous = AppDatabase(NativeDatabase(File(path)));
    await previous.into(previous.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant',
            canonicalName: 'Service',
            firstSeen: DateTime.utc(2026, 7, 1),
            lastSeen: DateTime.utc(2026, 7, 1),
          ),
        );
    await previous.customStatement(
      '''INSERT INTO transactions
         (id, ts, amount, direction, channel, parse_source, confidence_json,
          status, created_at, updated_at, currency_code, currency_symbol)
         VALUES ('legacy-txn', 1, 25, 'debit', 'card', 'template', '{}',
                 'auto', 1, 1, 'USD', '\$')''',
    );
    await previous.customStatement(
      '''INSERT INTO expected_events
         (id, source, label, expected_amount_paise, expected_date, state,
          confidence, dedup_key, currency_code, currency_symbol)
         VALUES ('legacy-event', 'sms_reminder', 'Service', 2500, 1,
                 'expected', 0.9, 'service_monthly_1', 'USD', '\$')''',
    );
    await previous.customStatement(
      '''INSERT INTO recurring_series
         (id, merchant_id, label, expected_amount, currency_code,
          currency_symbol, tolerance_pct, period, period_days,
          next_expected_date, last_amount, amount_trend, occurrences,
          status, kind)
         VALUES ('legacy-series', 'merchant', 'Service', 25, 'USD', '\$',
                 0.05, 'monthly', 30, 1, 25, 'flat', 3, 'active', 'subscription')''',
    );
    await previous.close();

    // Build a real v17 shape from the current schema, including existing rows.
    final raw = sqlite3.open(path);
    raw.execute('ALTER TABLE transactions DROP COLUMN currency_code');
    raw.execute('ALTER TABLE transactions DROP COLUMN currency_symbol');
    raw.execute('ALTER TABLE recurring_series DROP COLUMN currency_code');
    raw.execute('ALTER TABLE recurring_series DROP COLUMN currency_symbol');
    raw.execute('ALTER TABLE expected_events DROP COLUMN currency_code');
    raw.execute('ALTER TABLE expected_events DROP COLUMN currency_symbol');
    raw.execute('PRAGMA user_version = 17');
    raw.dispose();

    final migrated = AppDatabase(NativeDatabase(File(path)));
    addTearDown(migrated.close);
    final transaction =
        await migrated.select(migrated.transactions).getSingle();
    final series = await migrated.select(migrated.recurringSeries).getSingle();
    final event = await migrated.select(migrated.expectedEvents).getSingle();
    expect(transaction.currencyCode, isNull);
    expect(transaction.currencySymbol, isNull);
    expect(series.currencyCode, isNull);
    expect(series.currencySymbol, isNull);
    expect(event.currencyCode, isNull);
    expect(event.currencySymbol, isNull);
    final version =
        await migrated.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 18);
  });
}
