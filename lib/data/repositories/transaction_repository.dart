import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/normalized_transaction_record.dart';

/// A row of the transactions list, joined with merchant/category display
/// names in a single query (no per-row lookups).
class TransactionListItem {
  const TransactionListItem({
    required this.id,
    required this.ts,
    required this.amount,
    required this.direction,
    required this.displayName,
    required this.categoryName,
  });

  final String id;
  final DateTime ts;
  final double amount;
  final TransactionDirection direction;
  final String displayName;
  final String? categoryName;
}

/// Reads non-deleted transactions for list and dashboard screens.
class TransactionRepository {
  const TransactionRepository(this._database);

  final AppDatabase _database;

  /// Watches non-deleted transactions, newest first, with merchant and
  /// category names resolved in the same query.
  Stream<List<TransactionListItem>> watchTransactions() {
    final query = _database.select(_database.transactions).join([
      leftOuterJoin(
        _database.merchants,
        _database.merchants.id.equalsExp(_database.transactions.merchantId),
      ),
      leftOuterJoin(
        _database.categories,
        _database.categories.id.equalsExp(_database.transactions.categoryId),
      ),
    ])
      ..where(_database.transactions.isDeleted.equals(false))
      ..orderBy([OrderingTerm.desc(_database.transactions.ts)]);

    return query.watch().map(
          (rows) => rows.map(_toListItem).toList(growable: false),
        );
  }

  TransactionListItem _toListItem(TypedResult row) {
    final txn = row.readTable(_database.transactions);
    final merchant = row.readTableOrNull(_database.merchants);
    final category = row.readTableOrNull(_database.categories);
    return TransactionListItem(
      id: txn.id,
      ts: DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true),
      amount: txn.amount,
      direction: _directionFromWireName(txn.direction),
      displayName: merchant?.canonicalName ?? txn.merchantRaw ?? 'Unknown',
      categoryName: category?.name,
    );
  }
}

TransactionDirection _directionFromWireName(String wireName) {
  return TransactionDirection.values.firstWhere(
    (value) => value.wireName == wireName,
  );
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final transactionRepositoryProvider =
    Provider.family<TransactionRepository, AppDatabase>(
  (ref, database) => TransactionRepository(database),
);
