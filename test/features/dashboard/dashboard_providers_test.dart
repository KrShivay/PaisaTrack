import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

// The heavy aggregation semantics (analytics inclusion, settled-only,
// grouping, ordering, trend/previous windows) are exercised against the real
// SQL in test/data/repositories/dashboard_repository_test.dart. These tests
// pin only the provider-side projection of an already-computed aggregate, and
// prove the derived providers stay in loading/error rather than fabricating a
// number from the bounded transaction feed (PV-02).

DashboardAggregateSnapshot _snapshot({
  double debitTotal = 0,
  double creditTotal = 0,
  double previousSpend = 0,
  List<DashboardCategoryAggregate> categories = const [],
  List<DashboardMerchantAggregate> merchants = const [],
  Map<String, double> trendByMonth = const {},
}) {
  return DashboardAggregateSnapshot(
    debitTotal: debitTotal,
    creditTotal: creditTotal,
    previousSpend: previousSpend,
    categories: categories,
    merchants: merchants,
    trendByMonth: trendByMonth,
  );
}

TransactionListItem _item({
  required String id,
  required DateTime ts,
  required double amount,
  required TransactionDirection direction,
}) {
  return TransactionListItem(
    id: id,
    ts: ts,
    amount: amount,
    direction: direction,
    displayName: id,
    categoryName: null,
    categoryId: null,
    categoryIcon: null,
  );
}

Future<ProviderContainer> _ready(
  DashboardAggregateSnapshot snapshot, {
  DashboardPeriod? period,
}) async {
  final container = ProviderContainer(
    overrides: [
      dashboardAggregateProvider.overrideWith((ref) async => snapshot),
      if (period != null) dashboardPeriodProvider.overrideWith((ref) => period),
    ],
  );
  addTearDown(container.dispose);
  await container.read(dashboardAggregateProvider.future);
  return container;
}

void main() {
  final now = DateTime.now();

  test('monthNet is credit minus debit', () async {
    final c = await _ready(_snapshot(debitTotal: 300, creditTotal: 1000));
    expect(c.read(monthNetProvider).value, 700);
  });

  test('monthDirectionTotals project the aggregate', () async {
    final c = await _ready(_snapshot(debitTotal: 300, creditTotal: 1000));
    final totals = c.read(monthDirectionTotalsProvider).value!;
    expect(totals.debitTotal, 300);
    expect(totals.creditTotal, 1000);
  });

  test('dailyAverageSpend divides debit by elapsed days', () async {
    final c = await _ready(_snapshot(debitTotal: 300));
    expect(c.read(dailyAverageSpendProvider).value, 300 / now.day);
  });

  test('projectedMonthEndSpend scales current spend by days elapsed', () async {
    final c = await _ready(_snapshot(debitTotal: 300));
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    expect(
      c.read(projectedMonthEndSpendProvider).value,
      300 / now.day * daysInMonth,
    );
  });

  test('monthOverMonthSpend computes signed percent change', () async {
    final c = await _ready(_snapshot(debitTotal: 150, previousSpend: 100));
    final mom = c.read(monthOverMonthSpendProvider).value!;
    expect(mom.current, 150);
    expect(mom.previous, 100);
    expect(mom.pctChange, closeTo(0.5, 1e-9));
  });

  test('monthOverMonthSpend pctChange is null with no prior spend', () async {
    final c = await _ready(_snapshot(debitTotal: 150));
    expect(c.read(monthOverMonthSpendProvider).value!.pctChange, isNull);
  });

  test('categoryBreakdown computes share preserving aggregate order', () async {
    final c = await _ready(
      _snapshot(
        categories: const [
          DashboardCategoryAggregate(
            categoryId: 'food',
            name: 'Food',
            icon: null,
            total: 500,
          ),
          DashboardCategoryAggregate(
            categoryId: 'shopping',
            name: 'Shopping',
            icon: null,
            total: 500,
          ),
        ],
      ),
    );
    final slices = c.read(categoryBreakdownProvider).value!;
    expect(slices.length, 2);
    expect(slices.first.name, 'Food');
    expect(slices.first.share, closeTo(0.5, 1e-9));
    expect(slices[1].name, 'Shopping');
  });

  test('categoryBreakdown buckets overflow into Other', () async {
    final c = await _ready(
      _snapshot(
        categories: [
          for (var i = 0; i < 7; i++)
            DashboardCategoryAggregate(
              categoryId: 'cat$i',
              name: 'Cat$i',
              icon: null,
              total: (10 - i).toDouble(),
            ),
        ],
      ),
    );
    final slices = c.read(categoryBreakdownProvider).value!;
    expect(slices.length, 6); // 5 top + Other
    expect(slices.last.name, 'Other');
    expect(slices.last.total, 5 + 4); // two smallest: amounts 5 and 4
  });

  test('categoryBreakdown is empty when nothing was spent', () async {
    final c = await _ready(_snapshot());
    expect(c.read(categoryBreakdownProvider).value, isEmpty);
  });

  test('topMerchants project the aggregate rows', () async {
    final c = await _ready(
      _snapshot(
        merchants: const [
          DashboardMerchantAggregate(name: 'Swiggy', count: 2, total: 300),
          DashboardMerchantAggregate(name: 'Amazon', count: 1, total: 250),
        ],
      ),
    );
    final merchants = c.read(topMerchantsProvider).value!;
    expect(merchants.first.name, 'Swiggy');
    expect(merchants.first.total, 300);
    expect(merchants.first.count, 2);
    expect(merchants[1].name, 'Amazon');
  });

  test('sixMonthTrend returns six buckets oldest-first including current',
      () async {
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final c = await _ready(_snapshot(trendByMonth: {key: 500}));
    final trend = c.read(sixMonthTrendProvider).value!;
    expect(trend.length, 6);
    expect(trend.last.month.month, now.month);
    expect(trend.last.spend, 500);
    expect(trend.first.spend, 0);
  });

  group('no fabrication from the bounded feed', () {
    test('derived providers stay in loading until the aggregate resolves',
        () async {
      final container = ProviderContainer(
        overrides: [
          // Aggregate never completes.
          dashboardAggregateProvider.overrideWith(
            (ref) => Future<DashboardAggregateSnapshot>.delayed(
              const Duration(days: 1),
              _snapshot,
            ),
          ),
          // A populated bounded feed that must NOT be summed as a total.
          transactionListProvider.overrideWith(
            (ref) => Stream.value([
              _item(
                id: 'a',
                ts: now,
                amount: 999,
                direction: TransactionDirection.debit,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(transactionListProvider.future);

      expect(container.read(monthDirectionTotalsProvider).isLoading, isTrue);
      expect(container.read(monthNetProvider).isLoading, isTrue);
      expect(container.read(categoryBreakdownProvider).isLoading, isTrue);
      expect(container.read(topMerchantsProvider).isLoading, isTrue);
      expect(container.read(sixMonthTrendProvider).isLoading, isTrue);
    });

    test('derived providers surface error instead of feed totals', () async {
      final container = ProviderContainer(
        overrides: [
          dashboardAggregateProvider.overrideWith(
            (ref) => Future<DashboardAggregateSnapshot>.error(
              StateError('no db'),
            ),
          ),
          transactionListProvider.overrideWith(
            (ref) => Stream.value([
              _item(
                id: 'a',
                ts: now,
                amount: 999,
                direction: TransactionDirection.debit,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(transactionListProvider.future);
      await container
          .read(dashboardAggregateProvider.future)
          .catchError((_) => _snapshot());

      expect(container.read(monthDirectionTotalsProvider).hasError, isTrue);
      expect(container.read(monthNetProvider).hasError, isTrue);
      expect(container.read(categoryBreakdownProvider).hasError, isTrue);
    });
  });

  test('recentTransactions stays a bounded, period-filtered feed', () async {
    final period = DashboardPeriod.range(
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 12),
    );
    final container = ProviderContainer(
      overrides: [
        dashboardPeriodProvider.overrideWith((ref) => period),
        transactionListProvider.overrideWith(
          (ref) => Stream.value([
            _item(
              id: 'before',
              ts: DateTime(2026, 6, 9, 23, 59),
              amount: 900,
              direction: TransactionDirection.debit,
            ),
            _item(
              id: 'inside',
              ts: DateTime(2026, 6, 11, 12),
              amount: 120,
              direction: TransactionDirection.debit,
            ),
            _item(
              id: 'end',
              ts: DateTime(2026, 6, 12, 23, 59),
              amount: 500,
              direction: TransactionDirection.credit,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(transactionListProvider.future);
    expect(
      container.read(recentTransactionsProvider).map((item) => item.id),
      ['inside', 'end'],
    );
  });

  test('custom range comparison label is period-relative', () async {
    final period = DashboardPeriod.range(
      DateTime(2026, 7, 8),
      DateTime(2026, 7, 14),
    );
    final c = await _ready(
      _snapshot(debitTotal: 300, previousSpend: 200),
      period: period,
    );
    final comparison = c.read(monthOverMonthSpendProvider).value!;
    expect(comparison.current, 300);
    expect(comparison.previous, 200);
    expect(comparison.pctChange, 0.5);
    expect(period.comparisonLabel, 'vs previous period');
  });
}
