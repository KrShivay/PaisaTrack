import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/recurring_detector.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> merchant(String id, String name) {
    final firstSeen = DateTime.utc(2025);
    return database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: id,
            canonicalName: name,
            firstSeen: firstSeen,
            lastSeen: firstSeen,
          ),
        );
  }

  Future<void> txn({
    required String id,
    required String merchantId,
    required DateTime date,
    required double amount,
    String direction = 'debit',
  }) {
    return database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: date.millisecondsSinceEpoch,
            amount: amount,
            direction: direction,
            channel: 'card',
            merchantId: Value(merchantId),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'auto',
            createdAt: date,
            updatedAt: date,
          ),
        );
  }

  test('detects and idempotently upserts monthly subscription', () async {
    await merchant('streaming', 'StreamFlix');
    for (final entry in [
      ('s1', DateTime.utc(2026, 1, 1), 499.0),
      ('s2', DateTime.utc(2026, 1, 31), 500.0),
      ('s3', DateTime.utc(2026, 3, 2), 499.0),
      ('s4', DateTime.utc(2026, 4, 1), 501.0),
    ]) {
      await txn(
        id: entry.$1,
        merchantId: 'streaming',
        date: entry.$2,
        amount: entry.$3,
      );
    }

    final detector = RecurringDetector(database);
    await detector.run(today: DateTime.utc(2026, 4, 15));
    await detector.run(today: DateTime.utc(2026, 4, 15));

    final rows = await database.select(database.recurringSeries).get();
    expect(rows, hasLength(1));
    expect(rows.single.period, 'monthly');
    expect(rows.single.periodDays, 30);
    expect(rows.single.nextExpectedDate.toUtc(), DateTime.utc(2026, 5, 1));
    expect(rows.single.occurrences, 4);
    expect(rows.single.kind, 'subscription');
    expect(rows.single.status, 'active');
  });

  test('classifies EMI and rising last-three amounts', () async {
    await merchant('loan', 'Home Loan EMI');
    for (final entry in [
      ('e1', DateTime.utc(2026, 1, 5), 10000.0),
      ('e2', DateTime.utc(2026, 2, 4), 10100.0),
      ('e3', DateTime.utc(2026, 3, 6), 10200.0),
    ]) {
      await txn(
        id: entry.$1,
        merchantId: 'loan',
        date: entry.$2,
        amount: entry.$3,
      );
    }

    await RecurringDetector(database).run(today: DateTime.utc(2026, 3, 10));

    final row = await database.select(database.recurringSeries).getSingle();
    expect(row.kind, 'emi');
    expect(row.amountTrend, 'rising');
  });

  test('marks overdue income series missed after twenty-percent grace',
      () async {
    await merchant('employer', 'Payroll');
    for (final entry in [
      ('i1', DateTime.utc(2026, 1, 1)),
      ('i2', DateTime.utc(2026, 1, 31)),
      ('i3', DateTime.utc(2026, 3, 2)),
    ]) {
      await txn(
        id: entry.$1,
        merchantId: 'employer',
        date: entry.$2,
        amount: 50000,
        direction: 'credit',
      );
    }

    await RecurringDetector(database).run(today: DateTime.utc(2026, 4, 8));

    final row = await database.select(database.recurringSeries).getSingle();
    expect(row.kind, 'income');
    expect(row.status, 'missed');
  });

  test('rejects sparse, irregular, and separate amount-cluster noise',
      () async {
    await merchant('noise', 'Noise Merchant');
    for (final entry in [
      ('n1', DateTime.utc(2026, 1, 1), 100.0),
      ('n2', DateTime.utc(2026, 1, 8), 102.0),
      ('n3', DateTime.utc(2026, 3, 20), 300.0),
      ('n4', DateTime.utc(2026, 4, 19), 302.0),
    ]) {
      await txn(
        id: entry.$1,
        merchantId: 'noise',
        date: entry.$2,
        amount: entry.$3,
      );
    }
    await merchant('irregular', 'Irregular Merchant');
    for (final entry in [
      ('r1', DateTime.utc(2026, 1, 1)),
      ('r2', DateTime.utc(2026, 1, 30)),
      ('r3', DateTime.utc(2026, 1, 31)),
      ('r4', DateTime.utc(2026, 3, 1)),
    ]) {
      await txn(
        id: entry.$1,
        merchantId: 'irregular',
        date: entry.$2,
        amount: 700,
      );
    }

    final detections = await RecurringDetector(database).run();

    expect(detections, isEmpty);
    expect(await database.select(database.recurringSeries).get(), isEmpty);
  });
}
