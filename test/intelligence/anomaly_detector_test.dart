import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/anomaly_detector.dart';

void main() {
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> txn(String id, double amount) {
    final date = DateTime.utc(2026, 7, 8);
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: date.millisecondsSinceEpoch,
            amount: amount,
            direction: 'debit',
            channel: 'card',
            categoryId: const Value('shopping'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: date,
            updatedAt: date,
          ),
        );
  }

  test('incrementally updates a baseline once per period', () async {
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'shopping',
            name: 'Shopping',
            icon: 'shopping_bag',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await txn('t1', 80);
    await txn('t2', 20);
    final detector = AnomalyDetector(database);

    expect(await detector.run(today: DateTime.utc(2026, 7, 8)), 0);
    expect(await detector.run(today: DateTime.utc(2026, 7, 9)), 0);

    final baseline = await (database.select(database.baselines)
          ..where((b) => b.key.equals('cat:shopping:week')))
        .getSingle();
    expect(baseline.mean, 100);
    expect(baseline.std, 0);
    expect(baseline.n, 1);
  });

  test('flags above 2.5 sigma with top three contributors', () async {
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'shopping',
            name: 'Shopping',
            icon: 'shopping_bag',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.into(database.baselines).insert(
          BaselinesCompanion.insert(
            key: 'cat:shopping:week',
            mean: 100,
            std: 10,
            n: 8,
            updatedAt: DateTime.utc(2026, 6, 29),
          ),
        );
    await txn('largest', 60);
    await txn('second', 40);
    await txn('third', 20);
    await txn('fourth', 10);

    final flags =
        await AnomalyDetector(database).run(today: DateTime.utc(2026, 7, 8));

    expect(flags, 1);
    final insight = await database.select(database.insights).getSingle();
    final payload = jsonDecode(insight.payloadJson) as Map<String, Object?>;
    expect(payload['aggregate'], 130);
    expect(payload['threshold'], 125);
    expect(payload['top_transaction_ids'], ['largest', 'second', 'third']);
    final baseline = await database.select(database.baselines).getSingle();
    expect(baseline.n, 9);
    expect(baseline.mean, closeTo(103.333, 0.001));
  });
}
