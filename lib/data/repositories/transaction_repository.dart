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
    required this.categoryId,
    required this.categoryIcon,
  });

  final String id;
  final DateTime ts;
  final double amount;
  final TransactionDirection direction;
  final String displayName;
  final String? categoryName;
  final String? categoryId;
  final String? categoryIcon;
}

/// Reads non-deleted, non-suppressed transactions for list and dashboard
/// screens.
class TransactionRepository {
  const TransactionRepository(this._database);

  final AppDatabase _database;

  /// Watches user-visible transactions, newest first, with merchant and
  /// category display data resolved in the same query. Excludes rows the
  /// user deleted and rows suppressed as a cross-source duplicate echo
  /// (ADR 0003: `is_deleted` and `duplicate_of_txn_id` are independent).
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
      ..where(
        _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull(),
      )
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
      // Presentation-time fallback (merchant -> VPA); the write path keeps
      // the two signals independent (ADR 0003).
      displayName: merchant?.canonicalName ??
          txn.merchantRaw ??
          txn.counterpartyVpa ??
          'Unknown',
      categoryName: category?.name,
      categoryId: category?.id,
      categoryIcon: category?.icon,
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
