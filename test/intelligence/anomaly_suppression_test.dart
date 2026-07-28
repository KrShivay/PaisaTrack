import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/anomaly_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late AnomalyDetector detector;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.seedDefaultCategories();
    detector = AnomalyDetector(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('An annual premium in a detected recurring series raises a suppressed anomaly', () async {
    final now = DateTime.utc(2026, 7, 10);
    final monthStart = DateTime.utc(2026, 7, 1);

    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_lic',
            canonicalName: 'LIC Insurance',
            firstSeen: now,
            lastSeen: now,
          ),
        );

    // Baseline for merchant 'm_lic' (mean ₹100, std 10, 10 periods)
    await database.into(database.baselines).insert(
          BaselinesCompanion.insert(
            key: 'mer:m_lic:month',
            mean: 100.0,
            std: 10.0,
            n: 10,
            updatedAt: monthStart.subtract(const Duration(days: 35)),
          ),
        );

    // Active recurring series for LIC annual insurance
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'rec_lic',
            merchantId: 'm_lic',
            label: 'LIC Insurance',
            expectedAmount: 15000.0,
            period: 'yearly',
            periodDays: 365,
            nextExpectedDate: now,
            lastAmount: 15000.0,
            amountTrend: 'flat',
            occurrences: 3,
            status: 'active',
            kind: 'bill',
            tolerancePct: 0.05,
          ),
        );

    // Transaction for LIC insurance premium ₹15,000
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_lic',
            ts: monthStart.add(const Duration(days: 2)).millisecondsSinceEpoch,
            amount: 15000.0,
            direction: 'debit',
            channel: 'card',
            merchantId: const Value('m_lic'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final flags = await detector.run(today: now);
    expect(flags, 0); // 0 active unsuppressed alert flags

    final insights = await database.select(database.insights).get();
    final anomalies = insights.where((i) => i.kind == 'anomaly').toList();
    expect(anomalies, hasLength(1));
    expect(anomalies.first.payloadJson, contains('"suppressed":true'));
    expect(anomalies.first.payloadJson, contains('"suppression_reason":"recurring_series"'));
  });

  test('A small-rupee swing below the floor raises a suppressed anomaly', () async {
    final now = DateTime.utc(2026, 7, 10);
    final weekStart = DateTime.utc(2026, 7, 6); // Monday

    // Baseline for category 'food_dining' (mean ₹20, std 5, 10 periods)
    await database.into(database.baselines).insert(
          BaselinesCompanion.insert(
            key: 'cat:food_dining:week',
            mean: 20.0,
            std: 5.0,
            n: 10,
            updatedAt: weekStart.subtract(const Duration(days: 10)),
          ),
        );

    // Transaction for ₹150 (swing > 2.5σ but below ₹500 floor)
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_small',
            ts: weekStart.add(const Duration(days: 1)).millisecondsSinceEpoch,
            amount: 150.0,
            direction: 'debit',
            channel: 'upi',
            categoryId: const Value('food_dining'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final flags = await detector.run(today: now);
    expect(flags, 0); // 0 active flags below floor

    final insights = await database.select(database.insights).get();
    final anomalies = insights.where((i) => i.kind == 'anomaly').toList();
    expect(anomalies, hasLength(1));
    expect(anomalies.first.payloadJson, contains('"suppressed":true'));
    expect(anomalies.first.payloadJson, contains('"suppression_reason":"below_floor"'));
  });

  test('A genuine large deviation above floor without recurring series raises an active anomaly flag', () async {
    final now = DateTime.utc(2026, 7, 10);
    final monthStart = DateTime.utc(2026, 7, 1);

    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_hospital',
            canonicalName: 'Hospital',
            firstSeen: now,
            lastSeen: now,
          ),
        );

    // Baseline for merchant 'm_hospital' (mean ₹1000, std 200, 10 periods)
    await database.into(database.baselines).insert(
          BaselinesCompanion.insert(
            key: 'mer:m_hospital:month',
            mean: 1000.0,
            std: 200.0,
            n: 10,
            updatedAt: monthStart.subtract(const Duration(days: 35)),
          ),
        );

    // Large transaction for ₹25,000 (genuine anomaly)
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'txn_hospital',
            ts: monthStart.add(const Duration(days: 2)).millisecondsSinceEpoch,
            amount: 25000.0,
            direction: 'debit',
            channel: 'card',
            merchantId: const Value('m_hospital'),
            parseSource: 'template',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final flags = await detector.run(today: now);
    expect(flags, 1); // 1 active alert flag

    final insights = await database.select(database.insights).get();
    final anomaly = insights.firstWhere((i) => i.kind == 'anomaly');
    expect(anomaly.payloadJson, contains('"suppressed":false'));
  });
}
