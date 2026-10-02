import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/intelligence/claim.dart';
import 'package:paisatrack/intelligence/insights_engine.dart';

const utcCalendar = FinancialCalendar.fixed(Duration.zero);

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

  Future<void> category(String id, String name, {bool spending = true}) =>
      database.into(database.categories).insert(
            CategoriesCompanion.insert(
              id: id,
              name: name,
              icon: 'category',
              isSpending: spending,
              sortOrder: 1,
              isUserCreated: false,
            ),
          );

  Future<void> txn(
    String id,
    DateTime date,
    double amount,
    String? categoryId, {
    String? merchantId,
    String direction = 'debit',
    String? currencyCode,
    String? currencySymbol,
    String? ownedTransferId,
    bool analyticsExcluded = false,
    String lifecycleState = 'settled',
  }) =>
      database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: amount,
              direction: direction,
              channel: 'card',
              currencyCode: Value(currencyCode),
              currencySymbol: Value(currencySymbol),
              ownedTransferId: Value(ownedTransferId),
              isAnalyticsExcluded: Value(analyticsExcluded),
              lifecycleState: Value(lifecycleState),
              categoryId: Value(categoryId),
              merchantId: Value(merchantId),
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
    await category('subscriptions', 'Subscriptions');
    await txn('fee', DateTime.utc(2026, 7, 2), 25, 'fees_charges');
    await txn(
      'fee_later_this_month',
      DateTime.utc(2026, 7, 20),
      7,
      'fees_charges',
    );
    await txn('food_previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('food_current', DateTime.utc(2026, 7, 2), 150, 'food');
    await txn(
      'stream_previous',
      DateTime.utc(2026, 6, 3),
      100,
      'subscriptions',
      merchantId: 'streaming',
    );
    await txn(
      'stream_current',
      DateTime.utc(2026, 7, 3),
      120,
      'subscriptions',
      merchantId: 'streaming',
    );
    await txn(
      'utility_previous',
      DateTime.utc(2026, 6, 4),
      100,
      'subscriptions',
      merchantId: 'utility',
    );
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
    expect(result.generated, 7);
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
      32,
    );
    final delta = rows.firstWhere(
      (row) =>
          row.kind == 'category_delta' &&
          (jsonDecode(row.payloadJson)
                  as Map<String, dynamic>)['category_id'] ==
              'food',
    );
    expect(
      (jsonDecode(delta.payloadJson) as Map<String, Object?>)['delta_fraction'],
      0.5,
    );
    for (final row in rows.where((row) => row.kind != 'forecast')) {
      expect(
        const ClaimValidator().parse(row),
        isA<TypedClaim>(),
        reason: row.kind,
      );
    }
    expect(
      const ClaimValidator().parse(
        Insight(
          id: 'unknown-claim-id',
          period: fee.period,
          kind: fee.kind,
          payloadJson: fee.payloadJson,
          dismissed: false,
        ),
      ),
      isA<Null>(),
    );
  });

  test('category delta compares the same elapsed local days and records them',
      () async {
    const calendar = FinancialCalendar.fixed(Duration(hours: 5, minutes: 30));
    await category('food', 'Food');
    DateTime localDay(int month, int day) =>
        DateTime.utc(2026, month, day).subtract(calendar.timeZoneOffset);

    await txn('oct_food', localDay(10, 3), 800, 'food');
    await txn('sep_1', localDay(9, 1), 300, 'food');
    await txn('sep_2', localDay(9, 2), 300, 'food');
    await txn('sep_3', localDay(9, 3), 400, 'food');
    await txn('sep_later', localDay(9, 8), 8000, 'food');

    await InsightsEngine(database, calendar: calendar).run(
      today: DateTime.utc(2026, 10, 7, 8),
    );

    final rows = await (database.select(database.insights)
          ..where((row) => row.kind.equals('category_delta')))
        .get();
    final payload = jsonDecode(rows.single.payloadJson) as Map<String, Object?>;
    expect(payload['current_total'], 800);
    expect(payload['previous_total'], 1000);
    expect(payload['delta_fraction'], -0.2);
    expect(payload['current_start'], '2026-10-01');
    expect(payload['current_end'], '2026-10-07');
    expect(payload['previous_start'], '2026-09-01');
    expect(payload['previous_end'], '2026-09-07');
    expect(const ClaimValidator().parse(rows.single), isA<TypedClaim>());
  });

  test('suppresses early zero deltas and names uncategorised claims honestly',
      () async {
    await txn('previous_uncategorised', DateTime.utc(2026, 9, 2), 37304, null);
    final engine = InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    );

    await engine.run(today: DateTime.utc(2026, 10, 2));
    var rows = await (database.select(database.insights)
          ..where((row) => row.kind.equals('category_delta')))
        .get();
    expect(rows, isEmpty);

    await engine.run(today: DateTime.utc(2026, 10, 7));
    rows = await (database.select(database.insights)
          ..where((row) => row.kind.equals('category_delta')))
        .get();
    expect(rows, hasLength(1));

    const validator = ClaimValidator();
    final claim = validator.parse(rows.single)!;
    expect(claim.scope['category_id'], equals(null));
    expect(claim.metrics['current_total'], 0);
    expect(claim.metrics['previous_total'], 37304);
    final evidence = await database.select(database.transactions).get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isTrue);
    expect(
      const ClaimRenderer().render(claim)!.title,
      'Uncategorised spending',
    );
  });

  test('category delta keeps skipping a zero previous denominator', () async {
    await category('food', 'Food');
    await txn('oct_food', DateTime.utc(2026, 10, 3), 800, 'food');

    await InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    ).run(today: DateTime.utc(2026, 10, 3));

    final rows = await (database.select(database.insights)
          ..where((row) => row.kind.equals('category_delta')))
        .get();
    expect(rows, isEmpty);
  });

  test('fresh dashboard claims rank recent windows then larger changes',
      () async {
    await category('food', 'Food');
    await category('travel', 'Travel');
    await txn('food_previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('food_current', DateTime.utc(2026, 7, 2), 200, 'food');
    await txn('travel_previous', DateTime.utc(2026, 6, 3), 100, 'travel');
    await txn('travel_current', DateTime.utc(2026, 7, 3), 150, 'travel');
    await InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    ).run(today: DateTime.utc(2026, 7, 10));

    final rows = await database.select(database.insights).get();
    final fresh = await freshClaims(database, rows, calendar: utcCalendar);
    final claims =
        fresh.map(const ClaimValidator().parse).whereType<TypedClaim>();
    expect(claims.first.metrics['delta_fraction'], 1);
  });

  test('edited evidence invalidates its hash until claims are recomputed',
      () async {
    await category('food', 'Food');
    await txn('food_previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('food_current', DateTime.utc(2026, 7, 2), 150, 'food');
    final engine = InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    );
    await engine.run(today: DateTime.utc(2026, 7, 10));

    const validator = ClaimValidator();
    var row = (await database.select(database.insights).get()).single;
    var claim = validator.parse(row)!;
    var evidence = await (database.select(database.transactions)
          ..where((txn) => txn.id.isIn(claim.evidenceIds)))
        .get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isTrue);

    await (database.update(database.transactions)
          ..where((txn) => txn.id.equals('food_current')))
        .write(
      TransactionsCompanion(
        amount: const Value(175),
        updatedAt: Value(DateTime.utc(2026, 7, 10, 13)),
      ),
    );
    evidence = await (database.select(database.transactions)
          ..where((txn) => txn.id.isIn(claim.evidenceIds)))
        .get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isFalse);

    await engine.run(today: DateTime.utc(2026, 7, 10));
    row = (await database.select(database.insights).get()).single;
    claim = validator.parse(row)!;
    evidence = await (database.select(database.transactions)
          ..where((txn) => txn.id.isIn(claim.evidenceIds)))
        .get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isTrue);
    expect(claim.metrics['current_total'], 175);

    await (database.update(database.transactions)
          ..where((txn) => txn.id.equals('food_current')))
        .write(
      TransactionsCompanion(
        currencySymbol: const Value(r'$'),
        updatedAt: Value(DateTime.utc(2026, 7, 10, 14)),
      ),
    );
    evidence = await (database.select(database.transactions)
          ..where((txn) => txn.id.isIn(claim.evidenceIds)))
        .get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isFalse);
  });

  test('large category claims stay fresh and hash evidence after row 50',
      () async {
    await category('food', 'Food');
    for (var index = 0; index < 30; index++) {
      await txn('previous_$index', DateTime.utc(2026, 6, 2), 100, 'food');
      await txn('current_$index', DateTime.utc(2026, 7, 2), 150, 'food');
    }
    final engine = InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    );
    await engine.run(today: DateTime.utc(2026, 7, 10));

    const validator = ClaimValidator();
    final row = (await database.select(database.insights).get()).single;
    final claim = validator.parse(row)!;
    var evidence = await database.select(database.transactions).get();
    expect(claim.evidenceCount, 60);
    expect(claim.evidenceIds, hasLength(50));
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isTrue);
    expect(await freshClaims(database, [row], calendar: utcCalendar), [row]);

    await (database.update(database.transactions)
          ..where((txn) => txn.id.equals('previous_9')))
        .write(const TransactionsCompanion(amount: Value(175)));
    evidence = await database.select(database.transactions).get();
    expect(validator.isFresh(claim, evidence, calendar: utcCalendar), isFalse);
    expect(await freshClaims(database, [row], calendar: utcCalendar), isEmpty);
  });

  test('claim reads use the financial calendar at a local midnight boundary',
      () async {
    const calendar = FinancialCalendar.fixed(Duration(hours: -5));
    await category('food', 'Food');
    await txn('previous', DateTime.utc(2026, 8, 2, 5, 30), 100, 'food');
    // This instant is Sep 30 00:30 in America/New_York, but Sep 29 in the
    // configured fixed UTC-05:00 financial calendar.
    await txn(
      'boundary_current',
      DateTime.utc(2026, 9, 30, 4, 30),
      150,
      'food',
    );
    await InsightsEngine(database, calendar: calendar)
        .run(today: DateTime.utc(2026, 9, 29, 15));

    final row = (await database.select(database.insights).get()).single;
    final claim = const ClaimValidator().parse(row)!;
    final evidence = await database.select(database.transactions).get();
    expect(claim.evidenceIds, contains('boundary_current'));
    expect(
      const ClaimValidator().isFresh(claim, evidence, calendar: calendar),
      isTrue,
    );
    expect(await freshClaims(database, [row], calendar: calendar), [row]);
  });

  test('eligibility changes invalidate evidence even without updatedAt',
      () async {
    await category('food', 'Food');
    await txn('previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('current', DateTime.utc(2026, 7, 2), 150, 'food');
    final engine = InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    );
    await engine.run(today: DateTime.utc(2026, 7, 10));
    const validator = ClaimValidator();
    final claim = validator.parse(
      (await database.select(database.insights).get()).single,
    )!;

    for (final change in [
      const TransactionsCompanion(duplicateOfTxnId: Value('previous')),
      const TransactionsCompanion(ownedTransferId: Value('owned')),
      const TransactionsCompanion(isDeleted: Value(true)),
    ]) {
      await (database.update(database.transactions)
            ..where((txn) => txn.id.equals('current')))
          .write(change);
      final evidence = await database.select(database.transactions).get();
      expect(
        validator.isFresh(claim, evidence, calendar: utcCalendar),
        isFalse,
      );
      expect(
        await freshClaims(
          database,
          [(await database.select(database.insights).get()).single],
          calendar: utcCalendar,
        ),
        isEmpty,
      );
      await engine.run(today: DateTime.utc(2026, 7, 10));
      await (database.update(database.transactions)
            ..where((txn) => txn.id.equals('current')))
          .write(
        const TransactionsCompanion(
          duplicateOfTxnId: Value(null),
          ownedTransferId: Value(null),
          isDeleted: Value(false),
        ),
      );
      await engine.run(today: DateTime.utc(2026, 7, 10));
    }
  });

  test(
      'claim validator rejects unknown envelope, scope, window and metric keys',
      () async {
    await category('food', 'Food');
    await txn('previous', DateTime.utc(2026, 6, 2), 100, 'food');
    await txn('current', DateTime.utc(2026, 7, 2), 150, 'food');
    await InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    ).run(today: DateTime.utc(2026, 7, 10));
    final original = (await database.select(database.insights).get()).single;
    for (final target in ['claim', 'scope', 'window', 'metrics']) {
      final json = jsonDecode(original.payloadJson) as Map<String, dynamic>;
      final claim = json['claim'] as Map<String, dynamic>;
      final envelope = target == 'claim' ? claim : claim[target] as Map;
      envelope['unexpected'] = true;
      expect(
        const ClaimValidator().parse(
          Insight(
            id: original.id,
            period: original.period,
            kind: original.kind,
            payloadJson: jsonEncode(json),
            dismissed: false,
          ),
        ),
        isA<Null>(),
        reason: target,
      );
    }
  });

  test('coverage counts exclusions and keeps unknown currency separate',
      () async {
    await category('food', 'Food');
    await category('transfer', 'Transfer', spending: false);
    await txn(
      'inr_previous',
      DateTime.utc(2026, 6, 2),
      100,
      'food',
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await txn(
      'inr_current',
      DateTime.utc(2026, 7, 2),
      200,
      'food',
      currencyCode: 'INR',
      currencySymbol: '₹',
    );
    await txn('unknown_previous', DateTime.utc(2026, 6, 3), 50, 'food');
    await txn('unknown_current', DateTime.utc(2026, 7, 3), 100, 'food');
    await txn(
      'reversed_credit',
      DateTime.utc(2026, 7, 4),
      20,
      'food',
      direction: 'credit',
      lifecycleState: 'reversed',
    );
    await txn(
      'owned_transfer',
      DateTime.utc(2026, 7, 4),
      30,
      'food',
      ownedTransferId: 'transfer-pair',
    );
    await txn(
      'analytics_excluded',
      DateTime.utc(2026, 7, 4),
      40,
      'food',
      analyticsExcluded: true,
    );
    await txn('non_spending', DateTime.utc(2026, 7, 4), 50, 'transfer');
    await txn(
      'credit',
      DateTime.utc(2026, 7, 4),
      60,
      'food',
      direction: 'credit',
    );

    await InsightsEngine(
      database,
      calendar: const FinancialCalendar.fixed(Duration.zero),
    ).run(today: DateTime.utc(2026, 7, 10));

    final claims = (await database.select(database.insights).get())
        .map(const ClaimValidator().parse)
        .whereType<TypedClaim>()
        .toList();
    expect(claims, hasLength(2));
    final inr = claims.singleWhere(
      (claim) => claim.scope['currency_code'] == 'INR',
    );
    final unknown = claims.singleWhere(
      (claim) => claim.scope['currency_code'] == null,
    );
    expect(inr.metrics['current_total'], 200);
    expect(unknown.metrics['current_total'], 100);
    expect(
      const ClaimRenderer().render(
        unknown,
        categoryNames: {'food': 'Food'},
      )!.body,
      contains('currency unknown'),
    );
    final inrCoverage = inr.raw['coverage'] as Map<String, Object?>;
    expect(inrCoverage['rows'], 2);
    expect(inrCoverage['unknown_currency'], 0);
    expect(inrCoverage['excluded'], {
      'not_settled': 0,
      'owned_transfer': 0,
      'analytics_excluded': 0,
      'non_spending': 0,
      'credit': 0,
    });
    final unknownCoverage = unknown.raw['coverage'] as Map<String, Object?>;
    expect(unknownCoverage['rows'], 6);
    expect(unknownCoverage['unknown_currency'], 2);
    expect(unknownCoverage['unreviewed'], 0);
    expect(unknownCoverage['excluded'], {
      'not_settled': 1,
      'owned_transfer': 1,
      'analytics_excluded': 1,
      'non_spending': 0,
      'credit': 1,
    });
  });

  test('claim renderer ignores payload prose and only uses typed fields', () {
    const claim = TypedClaim(
      version: 1,
      calculation: 'category_delta@1',
      id: 'category_delta:2026-10:food:INR',
      scope: {
        'category_id': 'food',
        'currency_code': 'INR',
        'currency_symbol': null,
      },
      window: {
        'current': ['2026-10-01', '2026-10-03'],
        'previous': ['2026-09-01', '2026-09-03'],
      },
      metrics: {
        'current_total': 800,
        'previous_total': 1000,
        'delta_fraction': -0.2,
      },
      evidenceIds: ['a'],
      evidenceCount: 1,
      truncated: false,
      inputHash: 'hash',
      raw: {},
    );

    final display = const ClaimRenderer().render(
      claim,
      categoryNames: {'food': 'Food'},
    )!;
    expect(
      display.body,
      'Spent ₹800.00 vs ₹1,000.00 in the same days last month '
      '(Oct 1–3 vs Sep 1–3).',
    );
    expect(display.body.toLowerCase(), isNot(contains('should')));
    expect(display.body.toLowerCase(), isNot(contains('recommend')));
  });

  test('claim renderer formats every claim amount as a source amount', () {
    const renderer = ClaimRenderer();
    TypedClaim claim({
      required String calculation,
      required Map<String, num> metrics,
      Map<String, Object?> scope = const {
        'currency_code': 'INR',
        'currency_symbol': '₹',
      },
      Map<String, Object?> window = const {},
    }) =>
        TypedClaim(
          version: 1,
          calculation: calculation,
          id: calculation,
          scope: scope,
          window: window,
          metrics: metrics,
          evidenceIds: const ['one'],
          evidenceCount: 1,
          truncated: false,
          inputHash: 'hash',
          raw: const {},
        );

    final displays = [
      renderer.render(
        claim(
          calculation: 'category_delta@1',
          metrics: const {
            'current_total': 123456.7,
            'previous_total': 40,
          },
          scope: const {
            'category_id': 'food',
            'currency_code': 'INR',
            'currency_symbol': '₹',
          },
          window: const {
            'current': ['2026-10-01', '2026-10-01'],
            'previous': ['2026-09-01', '2026-09-02'],
          },
        ),
      )!,
      renderer.render(
        claim(
          calculation: 'fees_total@1',
          metrics: const {'total': 123456.7},
        ),
      )!,
      renderer.render(
        claim(
          calculation: 'price_creep@1',
          metrics: const {'expected_amount': 123456.7, 'last_amount': 40},
          scope: const {
            'merchant_id': 'm',
            'currency_code': 'USD',
            'currency_symbol': r'$',
          },
        ),
      )!,
      renderer.render(
        claim(
          calculation: 'duplicate_subscription@1',
          metrics: const {'monthly_total': 123456.7, 'series_count': 2},
          scope: const {'currency_symbol': r'$'},
        ),
      )!,
      renderer.render(
        claim(
          calculation: 'missed_autopay@1',
          metrics: const {'expected_amount': 123456.7},
          scope: const {
            'currency_code': 'INR',
            'currency_symbol': '₹',
            'merchant_id': 'm',
          },
        ),
      )!,
    ];

    expect(displays[0].body, contains('₹1,23,456.70 vs ₹40.00'));
    expect(displays[0].body, contains('(Oct 1 vs Sep 1–2).'));
    expect(displays[1].body, contains('₹1,23,456.70 in fees'));
    expect(displays[2].body, contains(r'$123456.70 USD to $40.00 USD'));
    expect(displays[3].body, contains(r'$123456.70 (currency unknown)'));
    expect(displays[4].body, contains('₹1,23,456.70 across'));
  });

  test('rerun is idempotent, preserves dismissal, and clears stale rows',
      () async {
    await merchant('streaming', 'Streaming');
    await category('food', 'Food');
    await txn(
      'stream-previous',
      DateTime.utc(2026, 6, 1, 12),
      90,
      'food',
      merchantId: 'streaming',
    );
    await txn(
      'stream-payment',
      DateTime.utc(2026, 7, 1, 12),
      100,
      'food',
      merchantId: 'streaming',
    );
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
    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((row) => row.kind == 'price_creep').dismissed,
      isTrue,
    );

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('stream-previous')))
        .write(const TransactionsCompanion(amount: Value(100)));
    await engine.run(today: DateTime.utc(2026, 7, 10));
    rows = await database.select(database.insights).get();
    expect(rows, isEmpty);
  });
}
