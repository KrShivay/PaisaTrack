import 'package:drift/drift.dart';

import '../db/database.dart';

class DashboardQueryWindow {
  const DashboardQueryWindow({
    required this.start,
    required this.end,
    required this.previousStart,
    required this.previousEnd,
    required this.trendStart,
    required this.trendEnd,
  });

  final DateTime start;
  final DateTime end;
  final DateTime previousStart;
  final DateTime previousEnd;
  final DateTime trendStart;
  final DateTime trendEnd;
}

class DashboardCategoryAggregate {
  const DashboardCategoryAggregate({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.total,
  });

  final String? categoryId;
  final String name;
  final String? icon;
  final double total;
}

class DashboardMerchantAggregate {
  const DashboardMerchantAggregate({
    required this.name,
    required this.count,
    required this.total,
  });

  final String name;
  final int count;
  final double total;
}

class DashboardAggregateSnapshot {
  const DashboardAggregateSnapshot({
    required this.debitTotal,
    required this.creditTotal,
    required this.previousSpend,
    required this.categories,
    required this.merchants,
    required this.trendByMonth,
  });

  final double debitTotal;
  final double creditTotal;
  final double previousSpend;
  final List<DashboardCategoryAggregate> categories;
  final List<DashboardMerchantAggregate> merchants;
  final Map<String, double> trendByMonth;
}

/// Runs dashboard arithmetic in SQLite so UI rebuild cost is independent of
/// total transaction history. Callers reuse the bounded transaction feed as
/// the change signal and reload these grouped aggregate result sets.
class DashboardRepository {
  const DashboardRepository(this._database);

  final AppDatabase _database;

  Future<DashboardAggregateSnapshot> load(
    DashboardQueryWindow window,
  ) async {
    final results = await Future.wait<Object>([
      _loadTotals(window),
      _loadCategories(window),
      _loadMerchants(window),
      _loadTrend(window),
    ]);
    final totals = results[0] as ({
      double debit,
      double credit,
      double previous,
    });
    return DashboardAggregateSnapshot(
      debitTotal: totals.debit,
      creditTotal: totals.credit,
      previousSpend: totals.previous,
      categories: results[1] as List<DashboardCategoryAggregate>,
      merchants: results[2] as List<DashboardMerchantAggregate>,
      trendByMonth: results[3] as Map<String, double>,
    );
  }

  Future<({double debit, double credit, double previous})> _loadTotals(
    DashboardQueryWindow window,
  ) async {
    final row = await _database.customSelect(
      '''
SELECT
  COALESCE(SUM(CASE
    WHEN t.ts >= ? AND t.ts < ? AND t.direction = 'debit'
      AND COALESCE(c.is_spending, 1) = 1 THEN t.amount ELSE 0 END), 0) AS debit,
  COALESCE(SUM(CASE
    WHEN t.ts >= ? AND t.ts < ? AND t.direction = 'credit'
      THEN t.amount ELSE 0 END), 0) AS credit,
  COALESCE(SUM(CASE
    WHEN t.ts >= ? AND t.ts < ? AND t.direction = 'debit'
      AND COALESCE(c.is_spending, 1) = 1 THEN t.amount ELSE 0 END), 0) AS previous
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL
''',
      variables: [
        Variable.withInt(window.start.millisecondsSinceEpoch),
        Variable.withInt(window.end.millisecondsSinceEpoch),
        Variable.withInt(window.start.millisecondsSinceEpoch),
        Variable.withInt(window.end.millisecondsSinceEpoch),
        Variable.withInt(window.previousStart.millisecondsSinceEpoch),
        Variable.withInt(window.previousEnd.millisecondsSinceEpoch),
      ],
      readsFrom: {_database.transactions, _database.categories},
    ).getSingle();
    return (
      debit: row.read<double>('debit'),
      credit: row.read<double>('credit'),
      previous: row.read<double>('previous'),
    );
  }

  Future<List<DashboardCategoryAggregate>> _loadCategories(
    DashboardQueryWindow window,
  ) async {
    final rows = await _database.customSelect(
      '''
SELECT t.category_id, COALESCE(c.name, 'Uncategorised') AS name, c.icon,
       SUM(t.amount) AS total
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE t.ts >= ? AND t.ts < ?
  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1
  AND t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL
GROUP BY t.category_id, c.name, c.icon
ORDER BY total DESC, name ASC
''',
      variables: [
        Variable.withInt(window.start.millisecondsSinceEpoch),
        Variable.withInt(window.end.millisecondsSinceEpoch),
      ],
      readsFrom: {_database.transactions, _database.categories},
    ).get();
    return [
      for (final row in rows)
        DashboardCategoryAggregate(
          categoryId: row.readNullable<String>('category_id'),
          name: row.read<String>('name'),
          icon: row.readNullable<String>('icon'),
          total: row.read<double>('total'),
        ),
    ];
  }

  Future<List<DashboardMerchantAggregate>> _loadMerchants(
    DashboardQueryWindow window,
  ) async {
    final rows = await _database.customSelect(
      '''
SELECT COALESCE(m.user_label, m.canonical_name, t.merchant_raw,
                t.counterparty_vpa, t.description, 'Unknown') AS name,
       COUNT(*) AS txn_count, SUM(t.amount) AS total
FROM transactions t
LEFT JOIN merchants m ON m.id = t.merchant_id
LEFT JOIN categories c ON c.id = t.category_id
WHERE t.ts >= ? AND t.ts < ?
  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1
  AND t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL
GROUP BY name
ORDER BY total DESC, name ASC
LIMIT 5
''',
      variables: [
        Variable.withInt(window.start.millisecondsSinceEpoch),
        Variable.withInt(window.end.millisecondsSinceEpoch),
      ],
      readsFrom: {
        _database.transactions,
        _database.categories,
        _database.merchants,
      },
    ).get();
    return [
      for (final row in rows)
        DashboardMerchantAggregate(
          name: row.read<String>('name'),
          count: row.read<int>('txn_count'),
          total: row.read<double>('total'),
        ),
    ];
  }

  Future<Map<String, double>> _loadTrend(
    DashboardQueryWindow window,
  ) async {
    final rows = await _database.customSelect(
      '''
SELECT strftime('%Y-%m', t.ts / 1000, 'unixepoch', 'localtime') AS month_key,
       SUM(t.amount) AS total
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE t.ts >= ? AND t.ts < ?
  AND t.direction = 'debit'
  AND COALESCE(c.is_spending, 1) = 1
  AND t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
  AND t.is_analytics_excluded = 0
  AND t.owned_transfer_id IS NULL
GROUP BY month_key
''',
      variables: [
        Variable.withInt(window.trendStart.millisecondsSinceEpoch),
        Variable.withInt(window.trendEnd.millisecondsSinceEpoch),
      ],
      readsFrom: {_database.transactions, _database.categories},
    ).get();
    return {
      for (final row in rows)
        row.read<String>('month_key'): row.read<double>('total'),
    };
  }
}
