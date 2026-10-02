import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/insights_engine.dart';

void main() {
  late AppDatabase database;
  late InsightsEngine engine;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    engine = InsightsEngine(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
      'Series crossing ±5% tolerance raises exactly 1 insight citing amounts; noise inside tolerance raises none',
      () async {
    final now = DateTime.utc(2026, 7, 10);
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_spotify',
            canonicalName: 'Spotify',
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm_netflix',
            canonicalName: 'Netflix',
            firstSeen: now,
            lastSeen: now,
          ),
        );

    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'spotify-previous',
            ts: DateTime.utc(2026, 6, 2).millisecondsSinceEpoch,
            amount: 119,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            direction: 'debit',
            channel: 'test',
            merchantId: const Value('m_spotify'),
            parseSource: 'test',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'spotify-current',
            ts: DateTime.utc(2026, 7, 2).millisecondsSinceEpoch,
            amount: 149,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            direction: 'debit',
            channel: 'test',
            merchantId: const Value('m_spotify'),
            parseSource: 'test',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Recorded occurrences, rather than recurring metadata, back the delta.
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'rec_spotify',
            merchantId: 'm_spotify',
            label: 'Spotify',
            expectedAmount: 119.0,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: now.add(const Duration(days: 15)),
            lastAmount: 149.0,
            amountTrend: 'rising',
            occurrences: 5,
            status: 'active',
            kind: 'subscription',
            tolerancePct: 0.05,
          ),
        );

    // Insert 1 series inside 5% tolerance (Netflix ₹499 -> ₹505 = +1.2% noise)
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'rec_netflix',
            merchantId: 'm_netflix',
            label: 'Netflix',
            expectedAmount: 499.0,
            currencyCode: const Value('INR'),
            currencySymbol: const Value('₹'),
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: now.add(const Duration(days: 15)),
            lastAmount: 505.0,
            amountTrend: 'flat',
            occurrences: 5,
            status: 'active',
            kind: 'subscription',
            tolerancePct: 0.05,
          ),
        );

    final result = await engine.run(today: now);
    expect(result.generated, greaterThan(0));

    final insights = await database.select(database.insights).get();
    final priceCreep = insights.where((i) => i.kind == 'price_creep').toList();

    expect(priceCreep, hasLength(1));
    expect(priceCreep.first.payloadJson, contains('"calc":"price_creep@1"'));
    expect(
      priceCreep.first.payloadJson,
      contains('"ids":["spotify-current","spotify-previous"]'),
    );
  });
}
