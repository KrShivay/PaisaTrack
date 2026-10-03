import 'package:drift/drift.dart';

import '../../enrichment/payee_identity_key.dart';
import '../../enrichment/trusted_category_outcome.dart';
import '../db/database.dart';
import 'rule_repository.dart';

class MerchantCategorySuggestion {
  const MerchantCategorySuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.supportingTransactionCount,
  });

  final String categoryId;
  final String categoryName;
  final int supportingTransactionCount;
}

class MerchantCategorySuggestionReceipt {
  const MerchantCategorySuggestionReceipt({
    required this.feedbackId,
    required this.beforeTransaction,
    required this.afterTransaction,
  });

  final String feedbackId;
  final Transaction beforeTransaction;
  final Transaction afterTransaction;
}

/// Reads exact-identity category suggestions and applies category-only receipts.
class MerchantCategorySuggestionRepository {
  const MerchantCategorySuggestionRepository(this._database);

  final AppDatabase _database;

  static const _confirmationContexts = {'activity_confirm', 'sort_confirm'};
  static const _categoryChoiceContexts = {
    'activity_swipe',
    'ask_now',
    'detail_chip_edit',
    'detail_edit',
    'merchant_suggestion_accept',
    'sort_categorize',
  };

  Future<MerchantCategorySuggestion?> suggestionFor(
    String transactionId,
  ) async {
    final target = await (_database.select(_database.transactions)
          ..where((row) => row.id.equals(transactionId)))
        .getSingleOrNull();
    if (target == null || !_eligibleTarget(target)) return null;

    final targetChoices = await (_database.select(_database.feedback)
          ..where(
            (row) =>
                row.txnId.equals(target.id) & row.field.equals('category_id'),
          ))
        .get();
    if (targetChoices.isNotEmpty) return null;

    final rule = await RuleRepository(_database).findMatch(
      merchantId: target.merchantId,
      merchantRaw: target.merchantRaw,
      counterpartyVpa: target.counterpartyVpa,
    );
    if (rule?.setCategoryId != null) return null;

    final targetVpa = _normalized(target.counterpartyVpa);
    final targetName = PayeeKey.keyFor(target.merchantRaw ?? '');
    if (targetVpa == null && targetName.isEmpty) return null;

    final evidenceTable = _database.payeeEvidence;
    final transactionsTable = _database.transactions;
    final identityValue = targetVpa ?? targetName;
    final evidenceType =
        targetVpa == null ? 'merchant_raw' : 'counterparty_vpa';
    final matchingRows = await (_database.select(transactionsTable).join([
      innerJoin(
        evidenceTable,
        evidenceTable.transactionId.equalsExp(transactionsTable.id),
      ),
    ])
          ..where(
            evidenceTable.evidenceType.equals(evidenceType) &
                evidenceTable.normalizedKey.equals(identityValue) &
                transactionsTable.id.isNotValue(target.id) &
                transactionsTable.parseSource.isNotValue('manual') &
                transactionsTable.categoryId.isNotNull() &
                transactionsTable.isDeleted.equals(false) &
                transactionsTable.isNotTransaction.equals(false) &
                transactionsTable.duplicateOfTxnId.isNull() &
                transactionsTable.isAnalyticsExcluded.equals(false) &
                transactionsTable.lifecycleState.equals('settled'),
          ))
        .get();
    final matchingTransactions = <String, Transaction>{};
    for (final joined in matchingRows) {
      final row = joined.readTable(transactionsTable);
      if (targetVpa != null &&
          _exactVpa(row.counterpartyVpa) != _exactVpa(target.counterpartyVpa)) {
        continue;
      }
      if (targetVpa == null &&
          PayeeKey.keyFor(row.merchantRaw ?? '') != targetName) {
        continue;
      }
      matchingTransactions[row.id] = row;
    }
    final matchedIds = matchingTransactions.keys.toSet();

    if (targetVpa == null) {
      final vpas = <String>{};
      for (final id in matchedIds) {
        final vpa = _exactVpa(matchingTransactions[id]?.counterpartyVpa);
        if (vpa != null) vpas.add(vpa);
      }
      if (vpas.length > 1) return null;
    }

    final candidateTransactionIds = _database.selectOnly(evidenceTable)
      ..addColumns([evidenceTable.transactionId])
      ..where(
        evidenceTable.evidenceType.equals(evidenceType) &
            evidenceTable.normalizedKey.equals(identityValue),
      );
    final feedback = await (_database.select(_database.feedback)
          ..where(
            (row) =>
                row.field.isIn(['category_id', 'status']) &
                row.txnId.isInQuery(candidateTransactionIds),
          ))
        .get();
    final feedbackByTransaction = <String, List<FeedbackData>>{};
    for (final row in feedback) {
      if (!matchedIds.contains(row.txnId)) continue;
      feedbackByTransaction.putIfAbsent(row.txnId, () => []).add(row);
    }
    int compareFeedback(FeedbackData a, FeedbackData b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    }

    final outcomes = <String, String>{};
    for (final id in matchedIds) {
      final row = matchingTransactions[id];
      if (row == null || !_eligibleHistory(row)) continue;
      if (!hasCategoryPredictionEvidence(row.confidenceJson)) continue;
      final events = feedbackByTransaction[id] ?? const <FeedbackData>[];
      final categoryEvents = events
          .where((event) => event.field == 'category_id')
          .toList()
        ..sort(compareFeedback);
      if (categoryEvents.isNotEmpty) {
        final latestChoice = categoryEvents.last;
        final chosenCategory = latestChoice.newValue;
        if (_categoryChoiceContexts.contains(latestChoice.context) &&
            chosenCategory != null &&
            chosenCategory == row.categoryId) {
          outcomes[id] = chosenCategory;
        }
        continue;
      }

      final statuses = events.where((event) => event.field == 'status').toList()
        ..sort(compareFeedback);
      final latestStatus = statuses.isEmpty ? null : statuses.last;
      if (row.status == 'confirmed' &&
          latestStatus?.newValue == 'confirmed' &&
          _confirmationContexts.contains(latestStatus?.context) &&
          row.categoryId != null) {
        outcomes[id] = row.categoryId!;
      }
    }

    if (outcomes.length < 2) return null;
    final categories = outcomes.values.toSet();
    if (categories.length != 1) return null;
    final categoryId = categories.single;
    if (categoryId == target.categoryId) return null;
    final category = await (_database.select(_database.categories)
          ..where((row) => row.id.equals(categoryId)))
        .getSingleOrNull();
    if (category == null) return null;
    return MerchantCategorySuggestion(
      categoryId: category.id,
      categoryName: category.name,
      supportingTransactionCount: outcomes.length,
    );
  }

  /// Revalidates and applies a suggestion atomically, changing only category.
  Future<MerchantCategorySuggestionReceipt?> acceptSuggestion({
    required String transactionId,
    required String categoryId,
    required Transaction expectedTransaction,
    DateTime Function() clock = DateTime.now,
    String Function(String transactionId, DateTime now)? feedbackIdFactory,
  }) {
    return _database.transaction(() async {
      final currentSuggestion = await suggestionFor(transactionId);
      if (currentSuggestion?.categoryId != categoryId) return null;
      final row = await (_database.select(_database.transactions)
            ..where((transaction) => transaction.id.equals(transactionId)))
          .getSingleOrNull();
      if (row == null ||
          !_eligibleTarget(row) ||
          row.categoryId == categoryId ||
          row != expectedTransaction) {
        return null;
      }
      final existingCategoryFeedback =
          await (_database.select(_database.feedback)
                ..where(
                  (feedback) =>
                      feedback.txnId.equals(transactionId) &
                      feedback.field.equals('category_id'),
                ))
              .get();
      if (existingCategoryFeedback.isNotEmpty) return null;
      final rule = await RuleRepository(_database).findMatch(
        merchantId: row.merchantId,
        merchantRaw: row.merchantRaw,
        counterpartyVpa: row.counterpartyVpa,
      );
      if (rule?.setCategoryId != null) return null;

      final now = clock().toUtc();
      final feedbackId = feedbackIdFactory?.call(transactionId, now) ??
          'fb_${transactionId}_category_id_${now.microsecondsSinceEpoch}';
      await (_database.update(_database.transactions)
            ..where((transaction) => transaction.id.equals(transactionId)))
          .write(
        TransactionsCompanion(
          categoryId: Value(categoryId),
          updatedAt: Value(now),
        ),
      );
      await _database.into(_database.feedback).insert(
            FeedbackCompanion.insert(
              id: feedbackId,
              txnId: transactionId,
              field: 'category_id',
              oldValue: Value(row.categoryId),
              newValue: Value(categoryId),
              context: 'merchant_suggestion_accept',
              modelConfidenceAtTime: const Value(null),
              createdAt: now,
            ),
          );
      final afterTransaction = await (_database.select(_database.transactions)
            ..where((transaction) => transaction.id.equals(transactionId)))
          .getSingle();
      return MerchantCategorySuggestionReceipt(
        feedbackId: feedbackId,
        beforeTransaction: row,
        afterTransaction: afterTransaction,
      );
    });
  }

  /// Reverses only the exact suggestion write; newer transaction edits win.
  Future<bool> undoSuggestion(
    MerchantCategorySuggestionReceipt receipt, {
    DateTime Function() clock = DateTime.now,
  }) {
    return _database.transaction(() async {
      final row = await (_database.select(_database.transactions)
            ..where(
              (transaction) =>
                  transaction.id.equals(receipt.afterTransaction.id),
            ))
          .getSingleOrNull();
      final feedback = await (_database.select(_database.feedback)
            ..where((entry) => entry.id.equals(receipt.feedbackId)))
          .getSingleOrNull();
      if (row == null ||
          feedback == null ||
          row != receipt.afterTransaction ||
          feedback.txnId != receipt.afterTransaction.id ||
          feedback.field != 'category_id' ||
          feedback.oldValue != receipt.beforeTransaction.categoryId ||
          feedback.newValue != receipt.afterTransaction.categoryId ||
          feedback.context != 'merchant_suggestion_accept' ||
          feedback.createdAt != receipt.afterTransaction.updatedAt) {
        return false;
      }
      await (_database.delete(_database.feedback)
            ..where((entry) => entry.id.equals(receipt.feedbackId)))
          .go();
      await (_database.update(_database.transactions)
            ..where(
              (transaction) =>
                  transaction.id.equals(receipt.afterTransaction.id),
            ))
          .write(
        TransactionsCompanion(
          categoryId: Value(receipt.beforeTransaction.categoryId),
          updatedAt: Value(clock().toUtc()),
        ),
      );
      return true;
    });
  }

  static bool _eligibleTarget(Transaction row) =>
      row.parseSource != 'manual' &&
      !row.isDeleted &&
      !row.isNotTransaction &&
      row.duplicateOfTxnId == null &&
      !row.isAnalyticsExcluded &&
      row.lifecycleState == 'settled';

  static bool _eligibleHistory(Transaction row) =>
      row.categoryId != null && _eligibleTarget(row);

  static String? _normalized(String? value) {
    final key = value == null ? '' : PayeeKey.keyFor(value);
    return key.isEmpty ? null : key;
  }

  static String? _exactVpa(String? value) {
    final key = value?.trim().toLowerCase();
    return key == null || key.isEmpty ? null : key;
  }
}
