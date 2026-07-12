import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';
import 'package:paisatrack/intelligence/assistant/query_engine.dart';

void main() {
  late AppDatabase database;
  late AssistantQueryEngine engine;
  final july = AssistantTimeRange(
    DateTime.utc(2026, 7),
    DateTime.utc(2026, 8),
    label: 'July',
  );
  final june = AssistantTimeRange(
    DateTime.utc(2026, 6),
    DateTime.utc(2026, 7),
    label: 'June',
  );

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    engine = AssistantQueryEngine(database);
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food',
            name: 'Food',
            icon: 'food',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'swiggy',
            canonicalName: 'Swiggy',
            firstSeen: DateTime.utc(2026),
            lastSeen: DateTime.utc(2026),
          ),
        );
  });
  tearDown(() => database.close());

  Future<void> txn(
    String id,
    DateTime date,
    double amount, {
    String direction = 'debit',
  }) =>
      database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: amount,
              direction: direction,
              channel: 'upi',
              merchantId: const Value('swiggy'),
              categoryId: const Value('food'),
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'auto',
              createdAt: date,
              updatedAt: date,
            ),
          );

  test('totals, merchant lookup, breakdown, and comparison are exact',
      () async {
    await txn('j1', DateTime.utc(2026, 7, 2), 100);
    await txn('j2', DateTime.utc(2026, 7, 3), 50);
    await txn('income', DateTime.utc(2026, 7, 4), 500, direction: 'credit');
    await txn('jun', DateTime.utc(2026, 6, 2), 75);

    AssistantIntent intent(
      AssistantIntentKind kind, {
      AssistantTimeRange? compare,
      String? merchant,
    }) =>
        AssistantIntent(
          kind: kind,
          metric: AssistantMetric.spend,
          aggregation: kind == AssistantIntentKind.categoryBreakdown
              ? AssistantAggregation.breakdown
              : AssistantAggregation.sum,
          range: july,
          compareRange: compare,
          merchant: merchant,
        );

    final total = await engine.run(intent(AssistantIntentKind.periodTotal))
        as TotalQueryResult;
    expect((total.value, total.count), (150, 2));
    final merchant = await engine.run(
      intent(AssistantIntentKind.merchantLookup, merchant: 'wigg'),
    ) as TotalQueryResult;
    expect(merchant.value, 150);
    final breakdown = await engine.run(
      intent(AssistantIntentKind.categoryBreakdown),
    ) as BreakdownQueryResult;
    expect(
      (breakdown.items.single.label, breakdown.items.single.total),
      ('Food', 150),
    );
    final comparison = await engine.run(
      intent(
        AssistantIntentKind.monthOverMonth,
        compare: june,
      ),
    ) as ComparisonQueryResult;
    expect(
      (comparison.current, comparison.previous, comparison.delta),
      (150, 75, 75),
    );
    expect(comparison.percent, 1);
  });

  test('upcoming recurring and active insights exclude out-of-scope rows',
      () async {
    await database.into(database.recurringSeries).insert(
          RecurringSeriesCompanion.insert(
            id: 'due',
            merchantId: 'swiggy',
            label: 'Swiggy One',
            expectedAmount: 99,
            tolerancePct: .05,
            period: 'monthly',
            periodDays: 30,
            nextExpectedDate: DateTime.utc(2026, 7, 20),
            lastAmount: 99,
            amountTrend: 'flat',
            occurrences: 3,
            status: 'active',
            kind: 'subscription',
          ),
        );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'active',
            period: '2026-07',
            kind: 'forecast',
            payloadJson: '{"projected_spend":123}',
          ),
        );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'dismissed',
            period: '2026-07',
            kind: 'anomaly',
            payloadJson: '{"aggregate":999}',
            dismissed: const Value(true),
          ),
        );
    final recurring = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.upcomingRecurring,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
      ),
    ) as RecurringQueryResult;
    expect(
      (recurring.items.single.label, recurring.items.single.amount),
      ('Swiggy One', 99),
    );
    final insights = await engine.run(
      const AssistantIntent(
        kind: AssistantIntentKind.activeInsights,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
      ),
    ) as InsightsQueryResult;
    expect(insights.items, hasLength(1));
    expect(insights.items.single.figures['projected_spend'], 123);
  });
}
