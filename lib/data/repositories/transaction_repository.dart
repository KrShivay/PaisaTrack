import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../models/normalized_transaction_record.dart';
import '../models/transaction_confidence_trail.dart';
import 'category_correction.dart';
import 'rule_repository.dart';
import '../../capture/template_engine/template_trust_ledger.dart';
import '../../enrichment/merchant_resolver.dart';

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
    this.categoryIsSpending = true,
    this.merchantId,
    this.merchantRaw,
    this.accountHint,
    this.channel = 'unknown',
    this.note,
    this.reference,
    this.status = 'confirmed',
    this.parseSource = 'unknown',
    this.paymentSourceId,
    this.paymentSourceName,
    this.includeInAnalytics = true,
    this.isOwnedTransfer = false,
  });

  final String id;
  final DateTime ts;
  final double amount;
  final TransactionDirection direction;
  final String displayName;
  final String? categoryName;
  final String? categoryId;
  final String? categoryIcon;
  final String? merchantId;
  final String? merchantRaw;
  final String? accountHint;
  final String channel;
  final String? note;
  final String? reference;
  final String status;
  final String parseSource;
  final String? paymentSourceId;
  final String? paymentSourceName;
  final bool includeInAnalytics;
  final bool isOwnedTransfer;

  /// Whether the category counts toward spending. Transfers and cash
  /// withdrawals are excluded (PLAN §5) and render in a neutral color rather
  /// than debit red (design-system.md §5). Defaults to true so callers and
  /// tests that omit it keep the prior spending behavior.
  final bool categoryIsSpending;
}

/// Review/ask queue row with enough context to render review surfaces and build
/// notification payloads.
class TransactionReviewItem {
  const TransactionReviewItem({
    required this.id,
    required this.ts,
    required this.amount,
    required this.direction,
    required this.displayName,
    required this.categoryName,
    required this.categoryId,
    required this.categoryIcon,
    required this.status,
    this.merchantRaw,
    this.counterpartyKey,
    this.isLowTrustParse = false,
  });

  final String id;
  final DateTime ts;
  final double amount;
  final TransactionDirection direction;
  final String displayName;
  final String? categoryName;
  final String? categoryId;
  final String? categoryIcon;
  final String status;
  final String? merchantRaw;

  /// Stable merchant/VPA/raw-merchant identity used to group review rows.
  final String? counterpartyKey;
  final bool isLowTrustParse;
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
    required this.confidenceTrail,
    required this.isLowTrustParse,
  });

  final Transaction txn;
  final String? merchantName;
  final String? categoryName;
  final double? parseConfidence;
  final TransactionConfidenceTrail confidenceTrail;
  final bool isLowTrustParse;
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
  Stream<List<TransactionListItem>> watchTransactions({
    int limit = 100,
    DateTime? start,
    DateTime? end,
  }) {
    assert(limit > 0);
    final query = _database.select(_database.transactions).join([
      leftOuterJoin(
        _database.merchants,
        _database.merchants.id.equalsExp(_database.transactions.merchantId),
      ),
      leftOuterJoin(
        _database.categories,
        _database.categories.id.equalsExp(_database.transactions.categoryId),
      ),
      leftOuterJoin(
        _database.paymentSources,
        _database.paymentSources.id
            .equalsExp(_database.transactions.paymentSourceId),
      ),
    ])
      ..where(
        _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull() &
            (start == null
                ? const Constant(true)
                : _database.transactions.ts.isBiggerOrEqualValue(
                    start.millisecondsSinceEpoch,
                  )) &
            (end == null
                ? const Constant(true)
                : _database.transactions.ts.isSmallerThanValue(
                    end.millisecondsSinceEpoch,
                  )),
      )
      ..orderBy([OrderingTerm.desc(_database.transactions.ts)])
      ..limit(limit);

    return query.watch().map(
          (rows) => rows.map(_toListItem).toList(growable: false),
        );
  }

  /// Watches transactions that need the weekly review batch flow.
  Stream<List<TransactionReviewItem>> watchReviewQueue({int limit = 100}) {
    assert(limit > 0);
    return _watchQueueWithStatus('needs_review', limit: limit);
  }

  /// Watches the small aggregate needed by Home and the Review header.
  /// Keeping this separate prevents those surfaces from materializing the
  /// complete review queue merely to compute a count, sum, and maximum.
  Stream<ReviewQueueSummary> watchReviewQueueSummary() {
    return _database
        .customSelect(
          '''
SELECT
  COUNT(*) AS item_count,
  COALESCE(SUM(t.amount), 0.0) AS total_amount,
  COUNT(DISTINCT COALESCE(
    t.merchant_id,
    t.counterparty_vpa,
    t.merchant_raw,
    t.description,
    t.id
  )) AS merchant_count,
  COALESCE((
    SELECT COALESCE(
      m.user_label,
      m.canonical_name,
      highest.merchant_raw,
      highest.counterparty_vpa,
      highest.description,
      'Unknown transaction'
    )
    FROM transactions AS highest
    LEFT JOIN merchants AS m ON m.id = highest.merchant_id
    WHERE highest.status = 'needs_review'
      AND highest.is_deleted = 0
      AND highest.duplicate_of_txn_id IS NULL
    ORDER BY highest.amount DESC
    LIMIT 1
  ), 'Unknown transaction') AS highest_impact_label
FROM transactions AS t
WHERE t.status = 'needs_review'
  AND t.is_deleted = 0
  AND t.duplicate_of_txn_id IS NULL
''',
          readsFrom: {_database.transactions, _database.merchants},
        )
        .watchSingle()
        .map(
          (row) => ReviewQueueSummary(
            count: row.read<int>('item_count'),
            amount: row.read<double>('total_amount'),
            merchantCount: row.read<int>('merchant_count'),
            highestImpactLabel: row.read<String>('highest_impact_label'),
          ),
        );
  }

  /// Watches transactions currently awaiting an ask-now answer.
  Stream<List<TransactionReviewItem>> watchAskQueue() {
    return _watchQueueWithStatus('asked');
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
      final confidenceTrail =
          TransactionConfidenceTrail.fromJson(txn.confidenceJson);
      return TransactionDetail(
        txn: txn,
        merchantName: switch (row.readTableOrNull(_database.merchants)) {
          final merchant? => merchant.userLabel ?? merchant.canonicalName,
          null => null,
        },
        categoryName: row.readTableOrNull(_database.categories)?.name,
        parseConfidence: confidenceTrail.parser?.confidence,
        confidenceTrail: confidenceTrail,
        isLowTrustParse: _isLowTrustParse(txn),
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
    Value<double> amount = const Value.absent(),
    Value<String> direction = const Value.absent(),
    Value<String?> merchantRaw = const Value.absent(),
    String context = 'detail_edit',
    bool recordParseCorrections = false,
    DateTime Function() clock = DateTime.now,
    String Function(String field)? feedbackIdFactory,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .getSingle();
      final now = clock().toUtc();
      final confidence = _parseConfidenceOf(row);
      if (amount.present && amount.value <= 0) {
        throw ArgumentError.value(amount.value, 'amount', 'must be positive');
      }
      if (direction.present &&
          direction.value != 'debit' &&
          direction.value != 'credit') {
        throw ArgumentError.value(
          direction.value,
          'direction',
          'must be debit or credit',
        );
      }
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
      stageEdit(
        field: 'amount',
        edit: amount.present
            ? Value<String?>(amount.value.toString())
            : const Value.absent(),
        oldValue: row.amount.toString(),
      );
      if (amount.present && amount.value != row.amount) {
        companion = companion.copyWith(amount: amount);
      }
      stageEdit(
        field: 'direction',
        edit: direction,
        oldValue: row.direction,
      );
      if (direction.present && direction.value != row.direction) {
        companion = companion.copyWith(direction: direction);
      }
      stageEdit(
        field: 'merchant_raw',
        edit: merchantRaw,
        oldValue: row.merchantRaw,
      );
      if (merchantRaw.present && merchantRaw.value != row.merchantRaw) {
        companion = companion.copyWith(merchantRaw: merchantRaw);
      }

      if (recordParseCorrections) {
        void stageParseVerdict(String field, bool changed) {
          if (!changed) return;
          feedbackRows.add(
            FeedbackCompanion.insert(
              id: feedbackId('parse_verdict_$field'),
              txnId: txnId,
              field: 'parse_verdict',
              newValue: Value('${field}_corrected'),
              context: 'parse_confirm',
              modelConfidenceAtTime: Value(confidence),
              createdAt: now,
            ),
          );
        }

        stageParseVerdict(
          'amount',
          amount.present && amount.value != row.amount,
        );
        stageParseVerdict(
          'direction',
          direction.present && direction.value != row.direction,
        );
        stageParseVerdict(
          'merchant',
          merchantRaw.present && merchantRaw.value != row.merchantRaw,
        );
      }

      if (feedbackRows.isEmpty) return 0;

      await (_database.update(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .write(companion);
      for (final feedbackRow in feedbackRows) {
        await _database.into(_database.feedback).insert(feedbackRow);
      }
      if (recordParseCorrections) {
        await TemplateTrustLedger(_database).refresh();
      }
      return feedbackRows.length;
    });
  }

  /// Records an explicit parse confirmation without changing transaction data.
  ///
  /// This has its own transaction boundary so a low-trust parse verdict is
  /// durable exactly once and can later feed the template trust ledger.
  Future<void> confirmParse({
    required String txnId,
    DateTime Function() clock = DateTime.now,
    String Function()? feedbackIdFactory,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .getSingle();
      final now = clock().toUtc();
      await _database.into(_database.feedback).insert(
            FeedbackCompanion.insert(
              id: feedbackIdFactory?.call() ??
                  'fb_${txnId}_parse_verdict_${now.microsecondsSinceEpoch}',
              txnId: txnId,
              field: 'parse_verdict',
              newValue: const Value('ok'),
              context: 'parse_confirm',
              modelConfidenceAtTime: Value(_parseConfidenceOf(row)),
              createdAt: now,
            ),
          );
      await TemplateTrustLedger(_database).refresh();
    });
  }

  /// Confirms a review row without changing its category.
  Future<void> confirm({
    required String txnId,
    DateTime Function() clock = DateTime.now,
  }) {
    return _database.transaction(() async {
      await (_database.update(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .write(
        TransactionsCompanion(
          status: const Value('confirmed'),
          updatedAt: Value(clock().toUtc()),
        ),
      );
    });
  }

  /// Confirms multiple review rows atomically without changing categories.
  ///
  /// Only rows still in `needs_review` are affected, so a stale selection
  /// cannot overwrite a newer ask/correction state. Returns the updated count.
  Future<int> confirmMany({
    required Iterable<String> txnIds,
    DateTime Function() clock = DateTime.now,
  }) {
    final ids = txnIds.toSet();
    if (ids.isEmpty) return Future.value(0);
    return _database.transaction(() {
      return (_database.update(_database.transactions)
            ..where(
              (t) => t.id.isIn(ids) & t.status.equals('needs_review'),
            ))
          .write(
        TransactionsCompanion(
          status: const Value('confirmed'),
          updatedAt: Value(clock().toUtc()),
        ),
      );
    });
  }

  /// Applies an ask-now or weekly-review correction in one database write
  /// boundary: rule insertion, feedback row(s), and transaction update all
  /// commit or roll back together.
  Future<int> correctWithRule({
    required String txnId,
    required String categoryId,
    String? description,
    required String context,
    DateTime Function() clock = DateTime.now,
    String Function(String field)? feedbackIdFactory,
  }) async {
    final result = await correctCategory(
      txnId: txnId,
      categoryId: categoryId,
      description:
          description == null ? const Value.absent() : Value(description),
      context: context,
      scope: CorrectionScope.futureMatching,
      clock: clock,
      feedbackIdFactory: feedbackIdFactory,
    );
    return result.feedbackCount;
  }

  /// Applies an explicit category correction scope without silently changing
  /// history. Rule creation and every selected transaction update share one
  /// database boundary.
  Future<CategoryCorrectionResult> correctCategory({
    required String txnId,
    required String categoryId,
    required CorrectionScope scope,
    required String context,
    Iterable<String> matchingTxnIds = const [],
    Value<String?> description = const Value.absent(),
    DateTime Function() clock = DateTime.now,
    String Function(String field)? feedbackIdFactory,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(_database.transactions)
            ..where((t) => t.id.equals(txnId)))
          .getSingle();
      final now = clock().toUtc();
      final ruleInput = _ruleInputFor(row);
      final willCreateRule = scope.createsRule && ruleInput != null;

      if (willCreateRule) {
        await RuleRepository(_database).insert(
          matchType: ruleInput.matchType,
          matchValue: ruleInput.matchValue,
          setCategoryId: categoryId,
          setDescription: description.present ? description.value : null,
          createdFromTxnId: txnId,
          clock: () => now,
        );
      }

      final targets = await _correctionTargets(
        current: row,
        scope: scope,
        ruleInput: ruleInput,
        matchingTxnIds: matchingTxnIds,
      );
      final feedbackRows = <FeedbackCompanion>[];

      void stageFeedback({
        required Transaction target,
        required String field,
        required String? oldValue,
        required String? newValue,
      }) {
        if (oldValue == newValue) return;
        final customId =
            target.id == txnId ? feedbackIdFactory?.call(field) : null;
        feedbackRows.add(
          FeedbackCompanion.insert(
            id: customId ??
                'fb_${target.id}_${field}_${now.microsecondsSinceEpoch}',
            txnId: target.id,
            field: field,
            oldValue: Value(oldValue),
            newValue: Value(newValue),
            context: context,
            modelConfidenceAtTime: Value(_parseConfidenceOf(target)),
            createdAt: now,
          ),
        );
      }

      for (final target in targets) {
        stageFeedback(
          target: target,
          field: 'category_id',
          oldValue: target.categoryId,
          newValue: categoryId,
        );
        if (target.id == txnId && description.present) {
          stageFeedback(
            target: target,
            field: 'description',
            oldValue: target.description,
            newValue: description.value,
          );
        }
        stageFeedback(
          target: target,
          field: 'status',
          oldValue: target.status,
          newValue: 'confirmed',
        );
        await (_database.update(_database.transactions)
              ..where((t) => t.id.equals(target.id)))
            .write(
          TransactionsCompanion(
            categoryId: Value(categoryId),
            description: target.id == txnId && description.present
                ? Value(description.value)
                : const Value.absent(),
            status: const Value('confirmed'),
            updatedAt: Value(now),
          ),
        );
      }
      // The correction's category feedback is the classifier training example.
      // When a resolver already linked this transaction, teach its normalized
      // raw spelling as a learned alias in the same transaction as the rule.
      final rawAlias = row.merchantRaw;
      if (willCreateRule &&
          row.merchantId != null &&
          rawAlias != null &&
          rawAlias.trim().isNotEmpty) {
        await _database.into(_database.merchantAliases).insertOnConflictUpdate(
              MerchantAliasesCompanion.insert(
                alias: MerchantResolver.normalizeAlias(rawAlias),
                merchantId: row.merchantId!,
                source: 'learned',
                confidence: 1,
              ),
            );
      }
      for (final feedbackRow in feedbackRows) {
        await _database.into(_database.feedback).insert(feedbackRow);
      }
      return CategoryCorrectionResult(
        feedbackCount: feedbackRows.length,
        affectedTransactionCount: targets.length,
        ruleCreated: willCreateRule,
      );
    });
  }

  Future<List<Transaction>> _correctionTargets({
    required Transaction current,
    required CorrectionScope scope,
    required _RuleInput? ruleInput,
    required Iterable<String> matchingTxnIds,
  }) async {
    if (scope == CorrectionScope.matchingGroup) {
      final ids = {...matchingTxnIds, current.id};
      return (_database.select(_database.transactions)
            ..where(
              (row) =>
                  row.id.isIn(ids) &
                  row.isDeleted.equals(false) &
                  row.duplicateOfTxnId.isNull(),
            ))
          .get();
    }
    if (scope == CorrectionScope.existingAndFuture && ruleInput != null) {
      final expected = ruleInput.matchValue.trim().toLowerCase();
      final query = _database.select(_database.transactions)
        ..where(
          (row) =>
              row.isDeleted.equals(false) & row.duplicateOfTxnId.isNull(),
        );

      if (ruleInput.matchType == 'counterparty') {
        query.where((row) => row.counterpartyVpa.lower().equals(expected));
      } else {
        query.where(
          (row) =>
              row.merchantRaw.lower().equals(expected) |
              row.merchantRaw.lower().like('$expected %') |
              row.merchantRaw.lower().like('$expected*%') |
              row.merchantRaw.lower().like('$expected-%') |
              row.merchantRaw.lower().like('$expected/%') |
              row.merchantRaw.lower().like('$expected.%'),
        );
      }
      return query.get();
    }
    return [current];
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

  /// Low-trust records require a user parse verdict under ADR 0005: generic
  /// parses, plus public-provenance templates that are capped below auto.
  bool _isLowTrustParse(Transaction txn) {
    if (txn.parseSource == 'generic') return true;
    try {
      final decoded = jsonDecode(txn.confidenceJson) as Map<String, Object?>;
      final parser = decoded['parser'] as Map<String, Object?>?;
      return parser?['provenance'] == 'public';
    } on FormatException {
      return false;
    } on TypeError {
      return false;
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

  Stream<List<TransactionReviewItem>> _watchQueueWithStatus(
    String status, {
    int? limit,
  }) {
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
        _database.transactions.status.equals(status) &
            _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull(),
      )
      ..orderBy([OrderingTerm.desc(_database.transactions.ts)]);
    if (limit != null) query.limit(limit);

    return query.watch().map(
          (rows) => rows.map(_toReviewItem).toList(growable: false),
        );
  }

  TransactionListItem _toListItem(TypedResult row) {
    final txn = row.readTable(_database.transactions);
    final merchant = row.readTableOrNull(_database.merchants);
    final category = row.readTableOrNull(_database.categories);
    final paymentSource = row.readTableOrNull(_database.paymentSources);
    return TransactionListItem(
      id: txn.id,
      ts: DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true),
      amount: txn.amount,
      direction: _directionFromWireName(txn.direction),
      // Presentation-time fallback (merchant -> VPA -> description); the
      // write path keeps the signals independent (ADR 0003). Description
      // covers manual entries, which have no merchant/VPA provenance.
      displayName: merchant?.userLabel ??
          merchant?.canonicalName ??
          txn.merchantRaw ??
          txn.counterpartyVpa ??
          txn.description ??
          'Unknown',
      categoryName: category?.name,
      categoryId: category?.id,
      categoryIcon: category?.icon,
      merchantId: txn.merchantId,
      merchantRaw: txn.merchantRaw,
      accountHint: txn.accountHint,
      channel: txn.channel,
      note: txn.description,
      reference: txn.refId,
      status: txn.status,
      parseSource: txn.parseSource,
      paymentSourceId: txn.paymentSourceId,
      paymentSourceName:
          paymentSource?.nickname ?? paymentSource?.maskedIdentifier,
      includeInAnalytics: !txn.isAnalyticsExcluded,
      isOwnedTransfer: txn.ownedTransferId != null,
      // Unknown/uncategorized defaults to spending; only an explicit
      // non-spending category (transfers, cash withdrawal) flips this.
      categoryIsSpending: category?.isSpending ?? true,
    );
  }

  TransactionReviewItem _toReviewItem(TypedResult row) {
    final txn = row.readTable(_database.transactions);
    final merchant = row.readTableOrNull(_database.merchants);
    final category = row.readTableOrNull(_database.categories);
    return TransactionReviewItem(
      id: txn.id,
      ts: DateTime.fromMillisecondsSinceEpoch(txn.ts, isUtc: true),
      amount: txn.amount,
      direction: _directionFromWireName(txn.direction),
      displayName: merchant?.userLabel ??
          merchant?.canonicalName ??
          txn.merchantRaw ??
          txn.counterpartyVpa ??
          txn.description ??
          'Unknown',
      categoryName: category?.name,
      categoryId: category?.id,
      categoryIcon: category?.icon,
      status: txn.status,
      merchantRaw: txn.merchantRaw,
      counterpartyKey: merchant != null
          ? 'merchant:${merchant.id}'
          : txn.counterpartyVpa != null
              ? 'vpa:${txn.counterpartyVpa!.trim().toLowerCase()}'
              : txn.merchantRaw != null
                  ? 'raw:${txn.merchantRaw!.trim().toLowerCase()}'
                  : 'txn:${txn.id}',
      isLowTrustParse: _isLowTrustParse(txn),
    );
  }
}

class ReviewQueueSummary {
  const ReviewQueueSummary({
    required this.count,
    required this.amount,
    required this.merchantCount,
    required this.highestImpactLabel,
  });

  final int count;
  final double amount;
  final int merchantCount;
  final String highestImpactLabel;
}

class _RuleInput {
  const _RuleInput({
    required this.matchType,
    required this.matchValue,
  });

  final String matchType;
  final String matchValue;
}

_RuleInput? _ruleInputFor(Transaction txn) {
  final vpa = txn.counterpartyVpa?.trim();
  if (vpa != null && vpa.isNotEmpty) {
    return _RuleInput(matchType: 'counterparty', matchValue: vpa);
  }
  final merchant = txn.merchantRaw?.trim();
  if (merchant != null && merchant.isNotEmpty) {
    return _RuleInput(matchType: 'merchant', matchValue: merchant);
  }
  return null;
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
