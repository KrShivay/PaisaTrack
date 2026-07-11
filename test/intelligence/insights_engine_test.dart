import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/insights_engine.dart';

void main() {
  late AppDatabase database;
  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> merchant(String id, String name) =>
      database.into(database.merchants).insert(
            MerchantsCompanion.insert(
              id: id,
              canonicalName: name,
              txnCount: const Value(0),
              firstSeen: DateTime.utc(2026),
              lastSeen: DateTime.utc(2026),
            ),
          );

  Future<void> category(String id, String name) =>
      database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: id,
              name: name,
              icon: 'category',
              isSpending: true,
              sortOrder: 1,
              isUserCreated: false,
            ),
          );

  Future<void> txn(
    String id,
    DateTime date,
    double amount,
    String categoryId,
  ) =>
      database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: amount,
              direction: 'debit',
              channel: 'card',
              categoryId: Value(categoryId),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'auto',
              createdAt: date,
              updatedAt: date,
            ),
          );

  Future<void> recurring({
    required String id,
    required String merchantId,
    String kind = 'subscription',
    String trend = 'flat',
    String status = 'active',
    double amount = 100,
  }) =>
      database.into(database.recurringSeries).insert(
            RecurringSeriesCompanion.insert(
              id: id,
              merchantId: merchantId,
              label: merchantId,
              expectedAmount: amount,
              tolerancePct: 0.05,
              period: 'monthly',
              periodDays: 30,
              nextExpectedDate: DateTime.utc(2026, 7, 20),
              lastAmount: amount,
              amountTrend: trend,
              occurrences: 4,
              status: status,
              kind: kind,
            ),
          );

  test('precomputes every deterministic insight kind', () async {
    await merchant('streaming', 'Streaming');
    await merchant('utility', 'Utility');
    await category('fees_charges', 'Fees & Charges');
    await category('food', 'Food');
    await txn('fee', DateTime.utc(2026, 7, 2), 25, 'fees_charges');
    await txn('food_previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('food_current', DateTime.utc(2026, 7, 2), 150, 'food');
    await recurring(id: 'stream_a', merchantId: 'streaming');
    await recurring(
      id: 'stream_b',
      merchantId: 'streaming',
      trend: 'rising',
      amount: 120,
    );
    await recurring(
      id: 'electricity',
      merchantId: 'utility',
      kind: 'bill',
      status: 'missed',
    );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'forecast:2026-07',
            period: '2026-07',
            kind: 'forecast',
            payloadJson: '{}',
          ),
        );

    final result = await InsightsEngine(database).run(
      today: DateTime.utc(2026, 7, 10),
    );

    expect(result.period, '2026-07');
    expect(result.generated, 5);
    expect(result.upstream, 1);
    final rows = await (database.select(database.insights)
          ..orderBy([(i) => OrderingTerm.asc(i.kind)]))
        .get();
    expect(
      rows.map((row) => row.kind),
      containsAll([
        'duplicate_subscription',
        'fees_total',
        'price_creep',
        'category_delta',
        'missed_autopay',
        'forecast',
      ]),
    );
    final fee = rows.singleWhere((row) => row.kind == 'fees_total');
    expect(
      (jsonDecode(fee.payloadJson) as Map<String, Object?>)['total'],
      25,
    );
    final delta = rows.singleWhere((row) => row.kind == 'category_delta');
    expect(
      (jsonDecode(delta.payloadJson) as Map<String, Object?>)['delta_fraction'],
      0.5,
    );
  });

  test('rerun is idempotent, preserves dismissal, and clears stale rows',
      () async {
    await merchant('streaming', 'Streaming');
    await recurring(
      id: 'stream',
      merchantId: 'streaming',
      trend: 'rising',
    );
    final engine = InsightsEngine(database);
    await engine.run(today: DateTime.utc(2026, 7, 10));
    await (database.update(database.insights)
          ..where((row) => row.id.equals('price_creep:2026-07:stream')))
        .write(const InsightsCompanion(dismissed: Value(true)));

    await engine.run(today: DateTime.utc(2026, 7, 10));
    var rows = await database.select(database.insights).get();
    expect(rows, hasLength(1));
    expect(rows.single.dismissed, isTrue);

    await (database.update(database.recurringSeries)
          ..where((row) => row.id.equals('stream')))
        .write(const RecurringSeriesCompanion(amountTrend: Value('flat')));
    await engine.run(today: DateTime.utc(2026, 7, 10));
    rows = await database.select(database.insights).get();
    expect(rows, isEmpty);
  });
}
