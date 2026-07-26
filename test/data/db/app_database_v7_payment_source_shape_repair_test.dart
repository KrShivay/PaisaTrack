import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v6->v7 adds payment source columns missing on upgraded devices',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('paisatrack_v7_repair_');
    final dbPath = '${tempDir.path}/paisatrack.db';
    addTearDown(() => tempDir.delete(recursive: true));
    _createV6DatabaseWithoutInstitution(dbPath);

    final database = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(database.close);

    final source = await database.select(database.paymentSources).getSingle();
    expect(source.id, 'source_xx1234_upi');
    expect(source.nickname, 'Primary UPI');
    expect(source.institution, isNull);

    final version =
        await database.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], database.schemaVersion);
  });
}

void _createV6DatabaseWithoutInstitution(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA user_version = 6');
    db.execute('''
      CREATE TABLE transactions (
        id TEXT NOT NULL PRIMARY KEY,
        channel TEXT NOT NULL,
        account_hint TEXT,
        payment_source_id TEXT,
        is_analytics_excluded INTEGER NOT NULL DEFAULT 0
      )
    ''');
    db.execute('''
      CREATE TABLE payment_sources (
        id TEXT NOT NULL PRIMARY KEY,
        kind TEXT NOT NULL,
        masked_identifier TEXT NOT NULL,
        nickname TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        include_in_analytics INTEGER NOT NULL DEFAULT 1,
        is_owned INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      INSERT INTO payment_sources
        (id, kind, masked_identifier, nickname, created_at, updated_at)
      VALUES (
        'source_xx1234_upi', 'upi', 'xx1234', 'Primary UPI',
        1782864000, 1782864000
      )
    ''');
  } finally {
    db.dispose();
  }
}
