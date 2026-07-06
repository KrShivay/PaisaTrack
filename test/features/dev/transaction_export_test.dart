import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/dev/transaction_export.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertTxn({
    required String id,
    required double amount,
    required String direction,
    String? refId,
    double? balanceAfter,
    bool isDeleted = false,
  }) {
    final now = DateTime.now();
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'upi',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            refId: Value(refId),
            balanceAfter: Value(balanceAfter),
            isDeleted: Value(isDeleted),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('serializeAll emits reconciliation schema incl. suppressed rows',
      () async {
    await insertTxn(
      id: 'txn_1',
      amount: 499.0,
      direction: 'debit',
      refId: '223047328116',
      balanceAfter: 1200.5,
    );
    await insertTxn(
      id: 'txn_2',
      amount: 499.0,
      direction: 'debit',
      refId: '223047328116',
      isDeleted: true, // suppressed duplicate must still be exported
    );

    final records = await TransactionJsonExporter(database).serializeAll();

    expect(records, hasLength(2));
    final first = records.firstWhere((r) => r['id'] == 'txn_1');
    expect(first['amount'], 499.0);
    expect(first['direction'], 'debit');
    expect(first['ref_id'], '223047328116');
    expect(first['balance_after'], 1200.5);
    expect(first['is_deleted'], false);
    expect(records.firstWhere((r) => r['id'] == 'txn_2')['is_deleted'], true);
  });

  test('exportTo writes parseable JSON file', () async {
    await insertTxn(id: 'txn_1', amount: 60.0, direction: 'credit');

    final dir = await Directory.systemTemp.createTemp('paisatrack_export');
    addTearDown(() => dir.delete(recursive: true));

    final file = await TransactionJsonExporter(database).exportTo(dir);

    expect(file.existsSync(), isTrue);
    final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
    expect(decoded, hasLength(1));
    expect((decoded.single as Map<String, dynamic>)['amount'], 60.0);
  });
}
