import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/burn_rate_forecaster.dart';

void main() {
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> txn(
    String id,
    DateTime date,
    double amount, {
    String direction = 'debit',
    bool deleted = false,
    String? duplicateOf,
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: date.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'card',
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            isDeleted: Value(deleted),
            duplicateOfTxnId: Value(duplicateOf),
            createdAt: date,
            updatedAt: date,
          ),
        );
  }

  test('projects current spend from trailing per-day medians', () async {
    for (final month in [4, 5, 6]) {
      await txn('m${month}d1', DateTime.utc(2026, month, 1), month * 10);
    }
    await txn('apr20', DateTime.utc(2026, 4, 20), 30);
    await txn('may20', DateTime.utc(2026, 5, 20), 50);
    await txn('jun20', DateTime.utc(2026, 6, 20), 40);
    await txn('apr30', DateTime.utc(2026, 4, 30), 10);
    await txn('may30', DateTime.utc(2026, 5, 30), 90);
    await txn('jun30', DateTime.utc(2026, 6, 30), 30);
    await txn('may31', DateTime.utc(2026, 5, 31), 90);
    await txn('current', DateTime.utc(2026, 7, 10), 100);
    await txn(
      'ignored-credit',
      DateTime.utc(2026, 7, 10),
      1000,
      direction: 'credit',
    );
    await txn(
      'ignored-deleted',
      DateTime.utc(2026, 7, 10),
      1000,
      deleted: true,
    );
    await txn('source', DateTime.utc(2026, 7, 10), 5);
    await txn(
      'ignored-duplicate',
      DateTime.utc(2026, 7, 10),
      1000,
      duplicateOf: 'source',
    );

    final forecast = await BurnRateForecaster(database).run(
      today: DateTime.utc(2026, 7, 10),
    );

    expect(forecast.currentSpend, 105);
    // Day 20 median = 40; day 30 median = 30; day 31 uses May only = 90.
    expect(forecast.remainingMedianSpend, 160);
    expect(forecast.projectedSpend, 265);
    expect(forecast.trailingAverage, closeTo(163.3333, 0.0001));
    expect(forecast.deviationFraction, closeTo(0.6224, 0.0001));
    expect(forecast.insightEmitted, isTrue);

    final insight = await database.select(database.insights).getSingle();
    expect(insight.id, 'forecast:2026-07');
    expect(insight.kind, 'forecast');
    final payload = jsonDecode(insight.payloadJson) as Map<String, Object?>;
    expect(payload['projected_spend'], 265);
    expect(payload['remaining_median_spend'], 160);
  });

  test('uses strict 10 percent threshold and clears a stale insight', () async {
    for (final month in [4, 5, 6]) {
      await txn('m$month', DateTime.utc(2026, month, 1), 100);
    }
    await txn('current', DateTime.utc(2026, 7, 10), 110);
    final forecaster = BurnRateForecaster(database);

    final boundary = await forecaster.run(today: DateTime.utc(2026, 7, 10));
    expect(boundary.deviationFraction, closeTo(0.10, 0.0000001));
    expect(boundary.insightEmitted, isFalse);
    expect(await database.select(database.insights).get(), isEmpty);

    await (database.update(database.transactions)
          ..where((t) => t.id.equals('current')))
        .write(const TransactionsCompanion(amount: Value(120)));
    expect(
      (await forecaster.run(today: DateTime.utc(2026, 7, 10))).insightEmitted,
      isTrue,
    );
    await (database.update(database.transactions)
          ..where((t) => t.id.equals('current')))
        .write(const TransactionsCompanion(amount: Value(100)));
    expect(
      (await forecaster.run(today: DateTime.utc(2026, 7, 10))).insightEmitted,
      isFalse,
    );
    expect(await database.select(database.insights).get(), isEmpty);
  });
}
