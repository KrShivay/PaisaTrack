import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/assistant/assistant_intent.dart';
import 'package:paisatrack/intelligence/assistant/answer_renderer.dart';
import 'package:paisatrack/intelligence/assistant/query_engine.dart';
import 'package:paisatrack/enrichment/payee_identity_key.dart';

import 'category_test_data.dart';

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
    String categoryId = 'food',
    String lifecycleState = 'settled',
    String? currencyCode,
    String? currencySymbol,
    String? merchantId = 'swiggy',
    String? merchantRaw,
    String? counterpartyVpa,
  }) =>
      database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: amount,
              currencyCode: Value(currencyCode),
              currencySymbol: Value(currencySymbol),
              direction: direction,
              channel: 'upi',
              merchantId: Value(merchantId),
              merchantRaw: Value(merchantRaw),
              counterpartyVpa: Value(counterpartyVpa),
              categoryId: Value(categoryId),
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'auto',
              lifecycleState: Value(lifecycleState),
              createdAt: date,
              updatedAt: date,
            ),
          );

  test(
    'totals, merchant lookup, breakdown, and comparison are exact',
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
        intent(AssistantIntentKind.merchantLookup, merchant: 'Swiggy'),
      ) as TotalQueryResult;
      expect(merchant.value, 150);
      final partialWord = await engine.run(
        intent(AssistantIntentKind.merchantLookup, merchant: 'wigg'),
      );
      expect(partialWord, isA<AssistantClarificationResult>());
      final breakdown =
          await engine.run(intent(AssistantIntentKind.categoryBreakdown))
              as BreakdownQueryResult;
      expect(
        (breakdown.items.single.label, breakdown.items.single.total),
        ('Food', 150),
      );
      final comparison = await engine.run(
        intent(AssistantIntentKind.monthOverMonth, compare: june),
      ) as ComparisonQueryResult;
      expect(
        (comparison.current, comparison.previous, comparison.delta),
        (150, 75, 75),
      );
      expect(comparison.percent, 1);
    },
  );

  test('merchant lookup resolves VPA, raw, aliases, and relabeled rows',
      () async {
    await (database.update(database.merchants)
          ..where((row) => row.id.equals('swiggy')))
        .write(const MerchantsCompanion(userLabel: Value('Food delivery')));
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: PayeeIdentityKey.normalize('Swiggy'),
            merchantId: 'swiggy',
            source: 'user',
            confidence: 1,
          ),
        );
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: PayeeKey.keyFor('swiggy@ybl'),
            merchantId: 'swiggy',
            source: 'user',
            confidence: 1,
          ),
        );
    await txn(
      'vpa_only',
      DateTime.utc(2026, 7, 2),
      100,
      merchantId: null,
      counterpartyVpa: 'swiggy@ybl',
    );
    await txn(
      'raw',
      DateTime.utc(2026, 7, 3),
      50,
      merchantId: null,
      merchantRaw: 'UPI-SWIGGY',
    );
    await txn(
      'labeled',
      DateTime.utc(2026, 7, 4),
      25,
      merchantRaw: 'Food delivery',
    );

    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.merchantLookup,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
        merchant: 'Swiggy',
      ),
    ) as TotalQueryResult;

    expect((result.value, result.count), (175, 3));
  });

  test('merchant phrase does not substring-match Coca Cola', () async {
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'coca',
            canonicalName: 'Coca Cola',
            firstSeen: DateTime.utc(2026),
            lastSeen: DateTime.utc(2026),
          ),
        );
    await txn(
      'coca_cola',
      DateTime.utc(2026, 7, 2),
      400,
      merchantId: 'coca',
      merchantRaw: 'Coca Cola',
    );

    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.merchantLookup,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
        merchant: 'ola',
      ),
    );

    expect(result, isA<AssistantClarificationResult>());
  });

  test('merchant phrase matching multiple payees asks for clarification',
      () async {
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'swiggy_two',
            canonicalName: 'Swiggy',
            firstSeen: DateTime.utc(2026),
            lastSeen: DateTime.utc(2026),
          ),
        );
    await txn(
      'swiggy_first',
      DateTime.utc(2026, 7, 2),
      100,
      merchantId: 'swiggy',
      merchantRaw: 'Swiggy',
      counterpartyVpa: 'first@ybl',
    );
    await txn(
      'swiggy_second',
      DateTime.utc(2026, 7, 3),
      100,
      merchantId: 'swiggy_two',
      merchantRaw: 'Swiggy',
      counterpartyVpa: 'second@okaxis',
    );
    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.merchantLookup,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
        merchant: 'Swiggy',
      ),
    );

    expect(result, isA<AssistantClarificationResult>());
    expect(
      const AnswerRenderer().render(
        AssistantIntent(
          kind: AssistantIntentKind.merchantLookup,
          metric: AssistantMetric.spend,
          aggregation: AssistantAggregation.sum,
          range: july,
          merchant: 'Swiggy',
        ),
        result,
      ),
      contains('more than one'),
    );
  });

  test('merchant ambiguity ignores payees with no eligible rows', () async {
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'swiggy_unspent',
            canonicalName: 'Swiggy',
            firstSeen: DateTime.utc(2026),
            lastSeen: DateTime.utc(2026),
          ),
        );
    await txn(
      'eligible_swiggy',
      DateTime.utc(2026, 7, 2),
      100,
      merchantId: 'swiggy',
      merchantRaw: 'Swiggy',
    );

    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.merchantLookup,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
        merchant: 'Swiggy',
      ),
    );

    expect(result, isA<TotalQueryResult>());
    expect((result as TotalQueryResult).count, 1);
  });

  test('same-label suggestion resolves back to the payee with that VPA handle',
      () async {
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'swiggy_alt',
            canonicalName: 'Swiggy',
            firstSeen: DateTime.utc(2026),
            lastSeen: DateTime.utc(2026),
          ),
        );
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: PayeeIdentityKey.normalize('swiggy@ybl'),
            merchantId: 'swiggy',
            source: 'user',
            confidence: 1,
          ),
        );
    await database.into(database.merchantAliases).insert(
          MerchantAliasesCompanion.insert(
            alias: PayeeIdentityKey.normalize('swiggy@okaxis'),
            merchantId: 'swiggy_alt',
            source: 'user',
            confidence: 1,
          ),
        );
    await txn(
      'swiggy_first',
      DateTime.utc(2026, 7, 2),
      100,
      merchantId: 'swiggy',
      merchantRaw: 'Swiggy',
      counterpartyVpa: 'swiggy@ybl',
    );
    await txn(
      'swiggy_second',
      DateTime.utc(2026, 7, 3),
      100,
      merchantId: 'swiggy_alt',
      merchantRaw: 'Swiggy',
      counterpartyVpa: 'swiggy@okaxis',
    );

    final intent = AssistantIntent(
      kind: AssistantIntentKind.merchantLookup,
      metric: AssistantMetric.spend,
      aggregation: AssistantAggregation.sum,
      range: july,
      merchant: 'Swiggy',
    );
    final result = await engine.run(intent);
    final answer = const AnswerRenderer().render(intent, result);

    expect(answer, contains('Swiggy'));
    expect(answer, contains('ybl'));
    expect(answer, contains('okaxis'));

    final suggestion = (result as AssistantClarificationResult)
        .refusal
        .suggestions
        .firstWhere((value) => value.endsWith('(ybl)'));
    final reasked = await engine.run(
      AssistantIntent(
        kind: intent.kind,
        metric: intent.metric,
        aggregation: intent.aggregation,
        range: intent.range,
        merchant: suggestion,
      ),
    ) as TotalQueryResult;
    expect((reasked.value, reasked.count), (100, 1));
  });

  test(
      'unknown merchant phrase asks for clarification instead of reporting zero',
      () async {
    await txn('swiggy_only', DateTime.utc(2026, 7, 2), 100);
    final intent = AssistantIntent(
      kind: AssistantIntentKind.merchantLookup,
      metric: AssistantMetric.spend,
      aggregation: AssistantAggregation.sum,
      range: july,
      merchant: 'Definitely not a payee',
    );

    final result = await engine.run(intent);
    final answer = const AnswerRenderer().render(intent, result);

    expect(result, isA<AssistantClarificationResult>());
    expect(answer, contains('matching payee'));
    expect(answer, isNot(contains('₹0')));
  });

  test('current month comparison uses matching elapsed days and labels them',
      () async {
    const calendar = FinancialCalendar.fixed(Duration(hours: -5));
    final now = DateTime.utc(2026, 10, 3, 15);
    engine = AssistantQueryEngine(
      database,
      calendar: calendar,
      clock: () => now,
    );
    DateTime localDay(int month, int day) =>
        calendar.day(2026, month, day).start.add(const Duration(hours: 12));

    await txn('oct', localDay(10, 3), 800);
    await txn('oct_future', localDay(10, 4), 7000);
    await txn('sep1', localDay(9, 1), 200);
    await txn('sep2', localDay(9, 2), 300);
    await txn('sep3', localDay(9, 3), 500);
    await txn('sep_later', localDay(9, 4), 8000);

    final current = calendar.month(2026, 10);
    final prior = calendar.month(2026, 9);
    final intent = AssistantIntent(
      kind: AssistantIntentKind.monthOverMonth,
      metric: AssistantMetric.spend,
      aggregation: AssistantAggregation.sum,
      range: AssistantTimeRange(current.start, current.end, label: '2026-10'),
      compareRange:
          AssistantTimeRange(prior.start, prior.end, label: '2026-09'),
    );
    final comparison = await engine.run(intent) as ComparisonQueryResult;

    expect(comparison.current, 800);
    expect(comparison.previous, 1000);
    expect(comparison.currentLabel, 'this month to date');
    expect(comparison.previousLabel, 'the same elapsed days last month');
    final answer = const AnswerRenderer().render(intent, comparison);
    expect(answer, contains('Current period (this month to date)'));
    expect(
      answer,
      contains('Previous period (the same elapsed days last month)'),
    );
  });

  test('completed month assistant comparison keeps full prior month', () async {
    const calendar = FinancialCalendar.fixed(Duration(hours: -5));
    final now = DateTime.utc(2026, 10, 3, 15);
    engine = AssistantQueryEngine(
      database,
      calendar: calendar,
      clock: () => now,
    );
    DateTime localDay(int month, int day) =>
        calendar.day(2026, month, day).start.add(const Duration(hours: 12));

    await txn('sep_early', localDay(9, 3), 800);
    await txn('sep_late', localDay(9, 30), 7000);
    await txn('aug_early', localDay(8, 1), 100);
    await txn('aug_late', localDay(8, 30), 900);

    final current = calendar.month(2026, 9);
    final prior = calendar.month(2026, 8);
    final intent = AssistantIntent(
      kind: AssistantIntentKind.monthOverMonth,
      metric: AssistantMetric.spend,
      aggregation: AssistantAggregation.sum,
      range: AssistantTimeRange(current.start, current.end, label: '2026-09'),
      compareRange:
          AssistantTimeRange(prior.start, prior.end, label: '2026-08'),
    );
    final comparison = await engine.run(intent) as ComparisonQueryResult;

    expect(comparison.current, 7800);
    expect(comparison.previous, 1000);
    expect(comparison.currentLabel, '2026-09');
    expect(comparison.previousLabel, '2026-08');
  });

  test('assistant totals keep explicit USD and bare dollar in separate buckets',
      () async {
    await txn(
      'inr',
      DateTime.utc(2026, 7, 2),
      100,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await txn(
      'usd',
      DateTime.utc(2026, 7, 3),
      100,
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await txn(
      'bare-dollar',
      DateTime.utc(2026, 7, 4),
      100,
      currencySymbol: r'$',
    );
    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.periodTotal,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.sum,
        range: july,
      ),
    ) as TotalQueryResult;

    expect(result.count, 3);
    expect(
      result.value,
      equals(null),
      reason: 'mixed currencies do not have a meaningful scalar total',
    );
    expect(result.currencyBuckets, hasLength(3));
    expect(result.currencyBuckets.map((bucket) => bucket.key).toSet(), {
      'code:INR',
      'code:USD',
      r'symbol:$',
    });
  });

  test('comparison keeps currencies that appear in only one period', () async {
    await txn(
      'current-inr',
      DateTime.utc(2026, 7, 2),
      500,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await txn(
      'current-usd',
      DateTime.utc(2026, 7, 3),
      20,
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await txn(
      'previous-inr',
      DateTime.utc(2026, 6, 2),
      300,
      currencyCode: 'INR',
      currencySymbol: '₹',
    );

    final intent = AssistantIntent(
      kind: AssistantIntentKind.monthOverMonth,
      metric: AssistantMetric.spend,
      aggregation: AssistantAggregation.sum,
      range: july,
      compareRange: june,
    );
    final comparison = await engine.run(intent) as ComparisonQueryResult;
    final answer = const AnswerRenderer().render(intent, comparison);

    expect(comparison.currencyBuckets, hasLength(2));
    final inr = comparison.currencyBuckets
        .singleWhere((bucket) => bucket.currencyCode == 'INR');
    final usd = comparison.currencyBuckets
        .singleWhere((bucket) => bucket.currencyCode == 'USD');
    expect((inr.current, inr.previous), (500.0, 300.0));
    expect((usd.current, usd.previous), (20.0, 0.0));
    expect(comparison.current, equals(null));
    expect(comparison.previous, equals(null));
    expect(comparison.delta, equals(null));
    expect(comparison.percent, equals(null));
    expect(answer, contains(r'$20.00 USD'));
    expect(answer, contains('₹500.00'));
    expect(answer, contains('₹300.00'));
  });

  test('category breakdown does not rank nominal totals across currencies',
      () async {
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'transport',
            name: 'Transport',
            icon: 'car',
            isSpending: true,
            sortOrder: 2,
            isUserCreated: false,
          ),
        );
    await txn(
      'food-usd',
      DateTime.utc(2026, 7, 2),
      300,
      categoryId: 'food',
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    await txn(
      'food-inr',
      DateTime.utc(2026, 7, 3),
      500,
      categoryId: 'food',
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await txn(
      'transport-usd',
      DateTime.utc(2026, 7, 4),
      1000,
      categoryId: 'transport',
      currencyCode: 'USD',
      currencySymbol: r'$',
    );

    final result = await engine.run(
      AssistantIntent(
        kind: AssistantIntentKind.categoryBreakdown,
        metric: AssistantMetric.spend,
        aggregation: AssistantAggregation.breakdown,
        range: july,
      ),
    ) as BreakdownQueryResult;

    expect(result.items.map((item) => item.label), [
      'Food',
      'Food',
      'Transport',
    ]);
    expect(result.items.map((item) => item.currencyCode), [
      'INR',
      'USD',
      'USD',
    ]);
    expect(result.items.map((item) => item.total), [500, 300, 1000]);
  });

  test(
    'upcoming recurring and active insights exclude out-of-scope rows',
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
      await database.into(database.insights).insert(
            InsightsCompanion.insert(
              id: 'model-authored',
              period: '2026-07',
              kind: 'narrative',
              payloadJson: '{"body":"Injected advice and a fake amount 999"}',
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
      expect(insights.items, isEmpty);
    },
  );

  test(
    'transaction predicates run in SQL before rows are materialized',
    () async {
      await txn('valid', DateTime.utc(2026, 7, 2), 100);
      final createdAt = DateTime.utc(2026, 7, 3);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'outside-dart-datetime-range',
              ts: 9223372036854775807,
              amount: 999,
              direction: 'debit',
              channel: 'upi',
              merchantId: const Value('swiggy'),
              categoryId: const Value('food'),
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'auto',
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          );

      final result = await engine.run(
        AssistantIntent(
          kind: AssistantIntentKind.periodTotal,
          metric: AssistantMetric.spend,
          aggregation: AssistantAggregation.sum,
          range: july,
        ),
      ) as TotalQueryResult;

      expect((result.value, result.count), (100, 1));
    },
  );

  test(
    'parent categories include descendants; exact children stay narrow',
    () async {
      const categoryIds = {
        'food_dining',
        'food_delivery',
        'food_dining_out',
        'groceries',
        'groceries_quick_commerce',
        'transfers',
      };
      for (final row in seededCategoryRows().where(
        (row) => categoryIds.contains(row['id']),
      )) {
        await database.into(database.categories).insert(
              CategoriesCompanion.insert(
                id: row['id']! as String,
                name: row['name']! as String,
                parentId: Value(row['parent_id'] as String?),
                icon: row['icon']! as String,
                isSpending: row['is_spending']! as bool,
                sortOrder: row['sort_order']! as int,
                isUserCreated: row['is_user_created']! as bool,
              ),
            );
      }
      await txn(
        'food-parent',
        DateTime.utc(2026, 7, 2),
        10,
        categoryId: 'food_dining',
      );
      await txn(
        'food-delivery',
        DateTime.utc(2026, 7, 3),
        20,
        categoryId: 'food_delivery',
      );
      await txn(
        'dining-out',
        DateTime.utc(2026, 7, 4),
        30,
        categoryId: 'food_dining_out',
      );
      await txn(
        'groceries',
        DateTime.utc(2026, 7, 5),
        40,
        categoryId: 'groceries',
      );
      await txn(
        'quick-commerce',
        DateTime.utc(2026, 7, 6),
        50,
        categoryId: 'groceries_quick_commerce',
      );
      await txn(
        'pending-food',
        DateTime.utc(2026, 7, 7),
        70,
        categoryId: 'food_delivery',
        lifecycleState: 'pending',
      );
      await txn(
        'transfer',
        DateTime.utc(2026, 7, 8),
        80,
        categoryId: 'transfers',
      );

      AssistantIntent categoryIntent({
        String? categoryId,
        List<String> categoryIds = const [],
      }) =>
          AssistantIntent(
            kind: AssistantIntentKind.periodTotal,
            metric: AssistantMetric.spend,
            aggregation: AssistantAggregation.sum,
            range: july,
            categoryId: categoryId,
            categoryIds: categoryIds,
          );

      final parent = await engine.run(categoryIntent(categoryId: 'food_dining'))
          as TotalQueryResult;
      final child = await engine
          .run(categoryIntent(categoryId: 'food_delivery')) as TotalQueryResult;
      final combined = await engine.run(
        categoryIntent(categoryIds: ['food_delivery', 'groceries']),
      ) as TotalQueryResult;
      final overlapping = await engine.run(
        categoryIntent(categoryIds: ['food_dining', 'food_delivery']),
      ) as TotalQueryResult;

      expect((parent.value, parent.count), (60, 3));
      expect((child.value, child.count), (20, 1));
      expect((combined.value, combined.count), (110, 3));
      expect((overlapping.value, overlapping.count), (60, 3));
    },
  );
}
