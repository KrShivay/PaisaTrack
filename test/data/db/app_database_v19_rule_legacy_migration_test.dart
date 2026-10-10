import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v18 merchant rules migrate to tagged legacy without schema changes',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v19_rules_');
    final path = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));

    final previous = AppDatabase(NativeDatabase(File(path)));
    await previous.into(previous.rules).insert(
          RulesCompanion.insert(
            id: 'old_merchant',
            matchType: 'merchant',
            matchValue: 'swiggy',
            createdAt: DateTime.utc(2026, 7, 1),
          ),
        );
    await previous.into(previous.rules).insert(
          RulesCompanion.insert(
            id: 'counterparty',
            matchType: 'counterparty',
            matchValue: 'friend@upi',
            createdAt: DateTime.utc(2026, 7, 1),
          ),
        );
    await previous.close();

    final raw = sqlite3.open(path);
    final schemaBefore = raw
        .select('PRAGMA table_info(rules)')
        .map((row) => row['name'])
        .toList();
    raw.execute('PRAGMA user_version = 18');
    raw.dispose();

    final migrated = AppDatabase(NativeDatabase(File(path)));
    addTearDown(migrated.close);
    final rows = await migrated.select(migrated.rules).get();
    expect(
      {for (final row in rows) row.id: row.matchType},
      {'old_merchant': 'merchant_legacy', 'counterparty': 'counterparty'},
    );

    final schemaAfter =
        await migrated.customSelect('PRAGMA table_info(rules)').get();
    expect(schemaAfter.map((row) => row.data['name']).toList(), schemaBefore);
    final version =
        await migrated.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], migrated.schemaVersion);

    // The migration's predicate is safe to retry and leaves tagged rows alone.
    await migrated.customStatement(
      "UPDATE rules SET match_type = 'merchant_legacy' "
      "WHERE match_type = 'merchant'",
    );
    expect(
      (await migrated.select(migrated.rules).get())
          .singleWhere((row) => row.id == 'old_merchant')
          .matchType,
      'merchant_legacy',
    );
  });
}
