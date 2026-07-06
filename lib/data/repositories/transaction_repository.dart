import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/normalized_transaction_record.dart';

/// User input for a manually entered transaction (T-037).
///
/// Manual entries have no SMS provenance: `parse_source` is `'manual'`,
/// confidence is 1.0, and status is `'confirmed'` (the user typed it, so
/// there is nothing to review). Channel defaults to cash — the common case
/// SMS capture can never see.
class ManualTransactionDraft {
  const ManualTransactionDraft({
    required this.amount,
    required this.direction,
    required this.ts,
    this.categoryId,
    this.description,
    this.channel = TransactionChannel.cash,
  });

  final double amount;
  final TransactionDirection direction;
  final DateTime ts;
  final String? categoryId;
  final String? description;
  final TransactionChannel channel;
}

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

/// Full detail of a single transaction for the detail screen (T-038):
/// the raw row (all frozen §6.2 fields) plus resolved display names and the
/// parse confidence extracted from `confidence_json`.
class TransactionDetail {
  const TransactionDetail({
    required this.txn,
    required this.merchantName,
    required this.categoryName,
    required this.parseConfidence,
  });

  final Transaction txn;
  final String? merchantName;
  final String? categoryName;
  final double? parseConfidence;
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

  /// Watches one transaction with resolved merchant/category names, or null
  /// when the id does not exist.
  Stream<TransactionDetail?> watchDetail(String txnId) {
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
      ..where(_database.transactions.id.equals(txnId));

    return query.watch().map((rows) {
      if (rows.isEmpty) return null;
      final row = rows.first;
      final txn = row.readTable(_database.transactions);
      return TransactionDetail(
        txn: txn,
        merchantName: row.readTableOrNull(_database.merchants)?.canonicalName,
        categoryName: row.readTableOrNull(_database.categories)?.name,
        parseConfidence: _parseConfidenceOf(txn),
      );
    });
  }

  /// Applies user edits to a transaction and records a `feedback` row per
  /// changed field, atomically (T-038): the update and its feedback rows
  /// commit or roll back together, so the learning loop can trust that every
  /// persisted edit has its provenance.
  ///
  /// [categoryId]/[description] use drift's [Value] so "not edited"
  /// (`Value.absent()`) is distinct from "cleared" (`Value(null)`). Fields
  /// whose new value equals the stored value are skipped. Returns the number
  /// of feedback rows written. [clock] and [feedbackIdFactory] are
  /// injectable for deterministic tests.
  Future<int> updateWithFeedback({
    required String txnId,
    Value<String?> categoryId = const Value.absent(),
    Value<String?> description = const Value.absent(),
    String context = 'detail_edit',
    DateTime Function() clock = DateTime.now,
    String Function(String field)? feedbackIdFactory,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .getSingle();
      final now = clock().toUtc();
      final confidence = _parseConfidenceOf(row);
      String feedbackId(String field) =>
          feedbackIdFactory?.call(field) ??
          'fb_${txnId}_${field}_${now.microsecondsSinceEpoch}';

      var companion = TransactionsCompanion(updatedAt: Value(now));
      final feedbackRows = <FeedbackCompanion>[];

      void stageEdit({
        required String field,
        required Value<String?> edit,
        required String? oldValue,
      }) {
        if (!edit.present || edit.value == oldValue) return;
        feedbackRows.add(
          FeedbackCompanion.insert(
            id: feedbackId(field),
            txnId: txnId,
            field: field,
            oldValue: Value(oldValue),
            newValue: Value(edit.value),
            context: context,
            modelConfidenceAtTime: Value(confidence),
            createdAt: now,
          ),
        );
      }

      stageEdit(
        field: 'category_id',
        edit: categoryId,
        oldValue: row.categoryId,
      );
      if (categoryId.present && categoryId.value != row.categoryId) {
        companion = companion.copyWith(categoryId: categoryId);
      }
      stageEdit(
        field: 'description',
        edit: description,
        oldValue: row.description,
      );
      if (description.present && description.value != row.description) {
        companion = companion.copyWith(description: description);
      }

      if (feedbackRows.isEmpty) return 0;

      await (_database.update(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .write(companion);
      for (final feedbackRow in feedbackRows) {
        await _database.into(_database.feedback).insert(feedbackRow);
      }
      return feedbackRows.length;
    });
  }

  /// Extracts the parse confidence from `confidence_json` (the `parser.c`
  /// entry SmsIngestor and insertManual write), or null when the payload has
  /// no parser entry (e.g. legacy rows).
  double? _parseConfidenceOf(Transaction txn) {
    try {
      final decoded = jsonDecode(txn.confidenceJson);
      final parser = (decoded as Map<String, Object?>)['parser'];
      final confidence = (parser as Map<String, Object?>?)?['c'];
      return (confidence as num?)?.toDouble();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Persists a manual entry and returns its id.
  ///
  /// Rows land `parse_source='manual'`, `status='confirmed'`, confidence 1.0
  /// so they render in the list and dashboard identically to parsed rows.
  /// [clock] is injectable for deterministic tests.
  Future<String> insertManual(
    ManualTransactionDraft draft, {
    DateTime Function() clock = DateTime.now,
  }) async {
    final now = clock().toUtc();
    final id = 'txn_manual_${now.microsecondsSinceEpoch}';
    await _database.into(_database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: draft.ts.toUtc().millisecondsSinceEpoch,
            amount: draft.amount,
            direction: draft.direction.wireName,
            channel: draft.channel.wireName,
            categoryId: Value(draft.categoryId),
            description: Value(draft.description),
            parseSource: ParseSource.manual.wireName,
            // Same shape SmsIngestor writes for parsed rows.
            confidenceJson: jsonEncode({
              'parser': {
                'c': 1.0,
                'src': ParseSource.manual.wireName,
              },
            }),
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
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
      // Presentation-time fallback (merchant -> VPA -> description); the
      // write path keeps the signals independent (ADR 0003). Description
      // covers manual entries, which have no merchant/VPA provenance.
      displayName: merchant?.canonicalName ??
          txn.merchantRaw ??
          txn.counterpartyVpa ??
          txn.description ??
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
