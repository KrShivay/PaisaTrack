import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

TransactionListItem _item({
  required String id,
  required DateTime ts,
  required double amount,
  required TransactionDirection direction,
  String? displayName,
  String? categoryId,
  String? categoryName,
  String? categoryIcon,
  bool categoryIsSpending = true,
  bool includeInAnalytics = true,
  bool isOwnedTransfer = false,
}) {
  return TransactionListItem(
    id: id,
    ts: ts,
    amount: amount,
    direction: direction,
    displayName: displayName ?? id,
    categoryName: categoryName,
    categoryId: categoryId,
    categoryIcon: categoryIcon,
    categoryIsSpending: categoryIsSpending,
    includeInAnalytics: includeInAnalytics,
    isOwnedTransfer: isOwnedTransfer,
  );
}

ProviderContainer _containerWith(
  List<TransactionListItem> items, {
  DashboardPeriod? period,
}) {
  final container = ProviderContainer(
    overrides: [
      transactionListProvider.overrideWith((ref) => Stream.value(items)),
      if (period != null) dashboardPeriodProvider.overrideWith((ref) => period),
    ],
  );
  // Prime the stream so downstream Providers see the value synchronously.
  addTearDown(container.dispose);
  return container;
}

void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5, 12);
  final lastMonth = DateTime(now.year, now.month - 1, 15, 12);

  Future<ProviderContainer> ready(
    List<TransactionListItem> items, {
    DashboardPeriod? period,
  }) async {
    final container = _containerWith(items, period: period);
    // Resolve the StreamProvider before reading derived providers.
    await container.read(transactionListProvider.future);
    return container;
  }

  test('monthNet is credit minus debit for the current month', () async {
    final c = await ready([
      _item(
        id: 'a',
        ts: thisMonth,
        amount: 300,
        direction: TransactionDirection.debit,
      ),
      _item(
        id: 'b',
        ts: thisMonth,
        amount: 1000,
        direction: TransactionDirection.credit,
      ),
      _item(
        id: 'old',
        ts: lastMonth,
        amount: 9999,
        direction: TransactionDirection.debit,
      ),
    ]);
    expect(c.read(monthNetProvider), 700);
  });

  test('spending aggregates exclude transfer debits', () async {
    final c = await ready([
      _item(
        id: 'spend',
        ts: thisMonth,
        amount: 300,
        direction: TransactionDirection.debit,
        categoryId: 'food',
        categoryName: 'Food',
      ),
      _item(
        id: 'transfer',
        ts: thisMonth,
        amount: 5000,
        direction: TransactionDirection.debit,
        categoryId: 'transfers',
        categoryName: 'Transfers',
        categoryIsSpending: false,
      ),
      _item(
        id: 'credit',
        ts: thisMonth,
        amount: 1000,
        direction: TransactionDirection.credit,
      ),
    ]);

    expect(c.read(monthDirectionTotalsProvider).debitTotal, 300);
    expect(c.read(monthNetProvider), 700);
    expect(c.read(categoryBreakdownProvider).single.name, 'Food');
    expect(c.read(topMerchantsProvider).single.name, 'spend');
  });

  test('analytics excludes opted-out sources and owned transfer pairs',
      () async {
    final c = await ready([
      _item(
        id: 'spend',
        ts: thisMonth,
        amount: 300,
        direction: TransactionDirection.debit,
      ),
      _item(
        id: 'excluded',
        ts: thisMonth,
        amount: 900,
        direction: TransactionDirection.debit,
        includeInAnalytics: false,
      ),
      _item(
        id: 'transfer-out',
        ts: thisMonth,
        amount: 500,
        direction: TransactionDirection.debit,
        isOwnedTransfer: true,
      ),
      _item(
        id: 'transfer-in',
        ts: thisMonth,
        amount: 500,
        direction: TransactionDirection.credit,
        isOwnedTransfer: true,
      ),
    ]);

    expect(c.read(monthDirectionTotalsProvider).debitTotal, 300);
    expect(c.read(monthDirectionTotalsProvider).creditTotal, 0);
    expect(c.read(monthNetProvider), -300);
  });

  test('dailyAverageSpend divides debit by day of month', () async {
    final c = await ready([
      _item(
        id: 'a',
        ts: thisMonth,
        amount: 300,
        direction: TransactionDirection.debit,
      ),
    ]);
    expect(c.read(dailyAverageSpendProvider), 300 / now.day);
  });

  test('projectedMonthEndSpend scales current spend by days elapsed', () async {
    final c = await ready([
      _item(
        id: 'a',
        ts: thisMonth,
        amount: 300,
        direction: TransactionDirection.debit,
      ),
    ]);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    expect(
      c.read(projectedMonthEndSpendProvider),
      300 / now.day * daysInMonth,
    );
  });

  test('monthOverMonthSpend computes signed percent change', () async {
    final c = await ready([
      _item(
        id: 'now',
        ts: thisMonth,
        amount: 150,
        direction: TransactionDirection.debit,
      ),
      _item(
        id: 'prev',
        ts: lastMonth,
        amount: 100,
        direction: TransactionDirection.debit,
      ),
    ]);
    final mom = c.read(monthOverMonthSpendProvider);
    expect(mom.current, 150);
    expect(mom.previous, 100);
    expect(mom.pctChange, closeTo(0.5, 1e-9));
  });

  test('monthOverMonthSpend pctChange is null with no prior spend', () async {
    final c = await ready([
      _item(
        id: 'now',
        ts: thisMonth,
        amount: 150,
        direction: TransactionDirection.debit,
      ),
    ]);
    expect(c.read(monthOverMonthSpendProvider).pctChange, isNull);
  });

  test('categoryBreakdown groups, sorts, and computes share', () async {
    final c = await ready([
      _item(
        id: 'f1',
        ts: thisMonth,
        amount: 400,
        direction: TransactionDirection.debit,
        categoryId: 'food_dining',
        categoryName: 'Food',
      ),
      _item(
        id: 'f2',
        ts: thisMonth,
        amount: 100,
        direction: TransactionDirection.debit,
        categoryId: 'food_dining',
        categoryName: 'Food',
      ),
      _item(
        id: 's1',
        ts: thisMonth,
        amount: 500,
        direction: TransactionDirection.debit,
        categoryId: 'shopping',
        categoryName: 'Shopping',
      ),
      _item(
        id: 'c1',
        ts: thisMonth,
        amount: 999,
        direction: TransactionDirection.credit,
        categoryId: 'income',
        categoryName: 'Income',
      ),
    ]);
    final slices = c.read(categoryBreakdownProvider);
    expect(slices.length, 2);
    // Equal totals (₹500 each): tie broken by name A→Z, so Food precedes Shopping.
    expect(slices.first.name, 'Food');
    expect(slices.first.total, 500);
    expect(slices.first.share, closeTo(0.5, 1e-9));
    expect(slices[1].name, 'Shopping');
    expect(slices[1].total, 500);
  });

  test('categoryBreakdown buckets overflow into Other', () async {
    final items = [
      for (var i = 0; i < 7; i++)
        _item(
          id: 'c$i',
          ts: thisMonth,
          amount: (10 - i).toDouble(),
          direction: TransactionDirection.debit,
          categoryId: 'cat$i',
          categoryName: 'Cat$i',
        ),
    ];
    final c = await ready(items);
    final slices = c.read(categoryBreakdownProvider);
    expect(slices.length, 6); // 5 top + Other
    expect(slices.last.name, 'Other');
    expect(slices.last.total, 5 + 4); // two smallest: amounts 5 and 4
  });

  test('topMerchants ranks by spend and counts payments', () async {
    final c = await ready([
      _item(
        id: 'm1',
        ts: thisMonth,
        amount: 100,
        direction: TransactionDirection.debit,
        displayName: 'Swiggy',
      ),
      _item(
        id: 'm2',
        ts: thisMonth,
        amount: 200,
        direction: TransactionDirection.debit,
        displayName: 'Swiggy',
      ),
      _item(
        id: 'm3',
        ts: thisMonth,
        amount: 250,
        direction: TransactionDirection.debit,
        displayName: 'Amazon',
      ),
    ]);
    final merchants = c.read(topMerchantsProvider);
    expect(merchants.first.name, 'Swiggy');
    expect(merchants.first.total, 300);
    expect(merchants.first.count, 2);
    expect(merchants[1].name, 'Amazon');
  });

  test('sixMonthTrend returns six buckets oldest-first including current',
      () async {
    final c = await ready([
      _item(
        id: 'a',
        ts: thisMonth,
        amount: 500,
        direction: TransactionDirection.debit,
      ),
    ]);
    final trend = c.read(sixMonthTrendProvider);
    expect(trend.length, 6);
    expect(trend.last.month.month, now.month);
    expect(trend.last.spend, 500);
    expect(trend.first.spend, 0);
  });

  test('custom range drives totals, categories, and recent transactions',
      () async {
    final period = DashboardPeriod.range(
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 12),
    );
    final c = await ready(
      [
        _item(
          id: 'before',
          ts: DateTime(2026, 6, 9, 23, 59),
          amount: 900,
          direction: TransactionDirection.debit,
          categoryName: 'Travel',
        ),
        _item(
          id: 'inside',
          ts: DateTime(2026, 6, 11, 12),
          amount: 120,
          direction: TransactionDirection.debit,
          categoryId: 'food',
          categoryName: 'Food',
        ),
        _item(
          id: 'end',
          ts: DateTime(2026, 6, 12, 23, 59),
          amount: 500,
          direction: TransactionDirection.credit,
        ),
      ],
      period: period,
    );

    expect(c.read(monthDirectionTotalsProvider).debitTotal, 120);
    expect(c.read(monthDirectionTotalsProvider).creditTotal, 500);
    expect(c.read(categoryBreakdownProvider).single.name, 'Food');
    expect(c.read(recentTransactionsProvider).map((item) => item.id), [
      'inside',
      'end',
    ]);
    expect(c.read(projectedMonthEndSpendProvider), isNull);
  });

  test('custom range compares against the immediately preceding equal period',
      () async {
    final period = DashboardPeriod.range(
      DateTime(2026, 7, 8),
      DateTime(2026, 7, 14),
    );
    final c = await ready(
      [
        _item(
          id: 'current',
          ts: DateTime(2026, 7, 10),
          amount: 300,
          direction: TransactionDirection.debit,
        ),
        _item(
          id: 'previous',
          ts: DateTime(2026, 7, 3),
          amount: 200,
          direction: TransactionDirection.debit,
        ),
      ],
      period: period,
    );

    final comparison = c.read(monthOverMonthSpendProvider);
    expect(comparison.current, 300);
    expect(comparison.previous, 200);
    expect(comparison.pctChange, 0.5);
    expect(period.comparisonLabel, 'vs previous period');
  });
}
