import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/anomaly_detector.dart';

void main() {
  const calendar = FinancialCalendar.fixed(Duration(hours: 5, minutes: 30));
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> txn(String id, double amount, [DateTime? timestamp]) {
    final date = timestamp ?? DateTime.utc(2026, 7, 8);
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: date.millisecondsSinceEpoch,
            amount: amount,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
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

  test('rebuilds completed-period baseline and excludes the partial period',
      () async {
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
    await txn('old-1', 80, DateTime.utc(2026, 6, 24));
    await txn('old-2', 20, DateTime.utc(2026, 6, 25));
    await txn('partial-1', 70, DateTime.utc(2026, 7, 7));
    final detector = AnomalyDetector(database, calendar: calendar);

    await detector.run(today: DateTime.utc(2026, 7, 8));
    await detector.run(today: DateTime.utc(2026, 7, 9));

    final baseline = await (database.select(database.baselines)
          ..where((b) => b.key.equals('cat:shopping|code:INR:week')))
        .getSingle();
    expect(baseline.mean, 50);
    expect(baseline.std, 50);
    expect(baseline.n, 2);
    expect(
      baseline.updatedAt.millisecondsSinceEpoch,
      DateTime.utc(2026, 6, 29)
          .subtract(calendar.timeZoneOffset)
          .millisecondsSinceEpoch,
    );
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
    for (var week = 1; week <= 8; week++) {
      await txn(
        'baseline-$week',
        100,
        DateTime.utc(2026, 7, 6).subtract(Duration(days: week * 7)),
      );
    }
    await txn('largest', 300);
    await txn('second', 200);
    final detector = AnomalyDetector(database, calendar: calendar);
    expect(await detector.run(today: DateTime.utc(2026, 7, 8)), 1);
    await txn('third', 100);
    await txn('fourth', 50);
    final flags = await detector.run(today: DateTime.utc(2026, 7, 8));

    expect(flags, 1);
    final insight = await database.select(database.insights).getSingle();
    final payload = jsonDecode(insight.payloadJson) as Map<String, Object?>;
    expect(payload['aggregate'], 650);
    expect(payload['threshold'], 100);
    expect(payload['top_transaction_ids'], ['largest', 'second', 'third']);
    final baseline = await database.select(database.baselines).getSingle();
    expect(baseline.n, 8);
    expect(baseline.mean, 100);
  });

  test('past-period correction rebuilds the rolling baseline', () async {
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
    await txn('past', 100, DateTime.utc(2026, 6, 24));
    final detector = AnomalyDetector(database, calendar: calendar);
    await detector.run(today: DateTime.utc(2026, 7, 8));
    var baseline = await (database.select(database.baselines)
          ..where((b) => b.key.equals('cat:shopping|code:INR:week')))
        .getSingle();
    expect(baseline.mean, 50);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('past')))
        .write(const TransactionsCompanion(amount: Value(300)));
    await detector.run(today: DateTime.utc(2026, 7, 8));
    baseline = await (database.select(database.baselines)
          ..where((b) => b.key.equals('cat:shopping|code:INR:week')))
        .getSingle();
    expect(baseline.mean, 150);
  });

  test('removes an anomaly when its current-period contributor is deleted',
      () async {
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
    for (var week = 1; week <= 8; week++) {
      await txn(
        'baseline-$week',
        100,
        DateTime.utc(2026, 7, 6).subtract(Duration(days: week * 7)),
      );
    }
    await txn('current', 900);
    final detector = AnomalyDetector(database, calendar: calendar);
    await detector.run(today: DateTime.utc(2026, 7, 8));
    expect(await database.select(database.insights).get(), hasLength(1));
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('current')))
        .write(const TransactionsCompanion(isNotTransaction: Value(true)));
    await detector.run(today: DateTime.utc(2026, 7, 8));
    expect(await database.select(database.insights).get(), isEmpty);
  });
}
