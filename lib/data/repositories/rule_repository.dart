import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../../enrichment/payee_identity_key.dart';

var _ruleIdSequence = 0;

class RuleMutation {
  const RuleMutation({
    required this.matchType,
    required this.matchValue,
    required this.previousRules,
    required this.writtenAt,
    required this.categoryId,
    required this.description,
    required this.createdFromTxnId,
    this.writtenRuleIds = const [],
  });

  final String matchType;
  final String matchValue;
  final List<Rule> previousRules;
  final DateTime writtenAt;
  final String? categoryId;
  final String? description;
  final String createdFromTxnId;
  final List<String> writtenRuleIds;
}

/// User-taught deterministic rules — step 1 of the categorizer ladder
/// (PLAN §7.4). Rules always win over probabilistic enrichment.
class RuleRepository {
  const RuleRepository(this._database);

  final AppDatabase _database;

  /// Strongest, newest rule matching the transaction's identity, or null.
  ///
  /// Exact VPA wins, then resolved merchant ID, exact normalized merchant
  /// identity, then a word-boundary fallback for tagged legacy rules. This
  /// keeps a user's per-VPA correction narrower than a merchant-wide rule.
  /// Unknown match_types never match.
  Future<Rule?> findMatch({
    String? merchantId,
    String? merchantRaw,
    String? counterpartyVpa,
  }) async {
    final rules = await _database.select(_database.rules).get()
      ..sort(_newestFirst);

    final vpa = _normalize(counterpartyVpa);
    if (vpa != null) {
      for (final rule in rules) {
        if (rule.matchType == 'counterparty' &&
            _normalize(rule.matchValue) == vpa) {
          return rule;
        }
      }
    }

    if (merchantId != null && merchantId.isNotEmpty) {
      for (final rule in rules) {
        if (rule.matchType == 'merchant_id' && rule.matchValue == merchantId) {
          return rule;
        }
      }
    }

    final merchantKey = merchantRaw == null
        ? null
        : normalizeMatchValue('merchant', merchantRaw);
    final merchantValue = merchantRaw;
    if (merchantKey != null &&
        merchantKey.isNotEmpty &&
        merchantValue != null) {
      for (final rule in rules) {
        if (rule.matchType == 'merchant' &&
            merchantKey == normalizeMatchValue('merchant', rule.matchValue)) {
          return rule;
        }
      }
      for (final rule in rules) {
        if (rule.matchType == 'merchant_legacy' &&
            WholePhraseMatcher(rule.matchValue).matches(merchantValue)) {
          return rule;
        }
      }
    }

    return null;
  }

  /// Replaces all legacy duplicates for one identity in the correction's
  /// transaction and keeps their prior values available for undo.
  Future<RuleMutation> replaceForIdentity({
    required String matchType,
    required String matchValue,
    String? setCategoryId,
    String? setDescription,
    required String createdFromTxnId,
    required DateTime now,
  }) async {
    final normalized = normalizeMatchValue(matchType, matchValue);
    final existing = await _database.select(_database.rules).get();
    final previous = existing
        .where(
          (rule) =>
              (rule.matchType == matchType ||
                  (matchType == 'merchant' &&
                      rule.matchType == 'merchant_legacy')) &&
              normalizeMatchValue(matchType, rule.matchValue) == normalized,
        )
        .toList()
      ..sort(_newestFirst);

    for (var offset = 0; offset < previous.length; offset += 400) {
      final ids = previous
          .skip(offset)
          .take(400)
          .map((rule) => rule.id)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        await (_database.delete(_database.rules)
              ..where((row) => row.id.isIn(ids)))
            .go();
      }
    }
    final writtenRuleId = await insert(
      matchType: matchType,
      matchValue: normalized,
      setCategoryId: setCategoryId,
      setDescription: setDescription,
      createdFromTxnId: createdFromTxnId,
      clock: () => now,
    );

    return RuleMutation(
      matchType: matchType,
      matchValue: normalized,
      previousRules: previous,
      writtenAt: now,
      categoryId: setCategoryId,
      description: setDescription,
      createdFromTxnId: createdFromTxnId,
      writtenRuleIds: [writtenRuleId],
    );
  }

  /// Restores the prior identity mapping only if this correction still owns it.
  Future<bool> restoreMutation(RuleMutation mutation) async {
    if (mutation.writtenRuleIds.isEmpty) return false;
    final writtenIds = mutation.writtenRuleIds.toSet();
    final current = await _database.select(_database.rules).get();
    final matching = current
        .where(
          (rule) =>
              (rule.matchType == mutation.matchType ||
                  (mutation.matchType == 'merchant' &&
                      rule.matchType == 'merchant_legacy')) &&
              normalizeMatchValue(mutation.matchType, rule.matchValue) ==
                  mutation.matchValue,
        )
        .toList();
    final ownedRules = matching
        .where((rule) => writtenIds.contains(rule.id))
        .toList(growable: false);
    if (matching.length != writtenIds.length ||
        ownedRules.length != writtenIds.length ||
        ownedRules.any(
          (rule) =>
              rule.matchType != mutation.matchType ||
              rule.matchValue != mutation.matchValue ||
              rule.setCategoryId != mutation.categoryId ||
              rule.setDescription != mutation.description ||
              rule.createdFromTxnId != mutation.createdFromTxnId ||
              rule.hitCount != 0,
        )) {
      return false;
    }

    if (mutation.previousRules.isEmpty) {
      await (_database.delete(_database.rules)
            ..where((rule) => rule.id.isIn(writtenIds)))
          .go();
    } else {
      final oldIds = mutation.previousRules.map((rule) => rule.id).toSet();
      await (_database.delete(_database.rules)
            ..where(
              (rule) => rule.id.isIn(writtenIds) & rule.id.isNotIn(oldIds),
            ))
          .go();
      for (final rule in mutation.previousRules) {
        await _database.into(_database.rules).insertOnConflictUpdate(
              rule.toCompanion(true),
            );
      }
    }
    return true;
  }

  static String normalizeMatchValue(String matchType, String value) =>
      matchType == 'merchant'
          ? PayeeIdentityKey.normalize(value)
          : matchType == 'merchant_id'
              ? value.trim()
              : value.toLowerCase().trim();

  static int _newestFirst(Rule a, Rule b) {
    final byCreatedAt = b.createdAt.compareTo(a.createdAt);
    return byCreatedAt != 0 ? byCreatedAt : b.id.compareTo(a.id);
  }

  /// Records one application of [ruleId] (PLAN §6: rules carry hit counts).
  Future<void> incrementHitCount(String ruleId) async {
    await _database.customUpdate(
      'UPDATE rules SET hit_count = hit_count + 1 WHERE id = ?',
      variables: [Variable.withString(ruleId)],
      updates: {_database.rules},
    );
  }

  /// Creates a rule taught by a user correction (ask flow / review flows).
  Future<String> insert({
    required String matchType,
    required String matchValue,
    String? setCategoryId,
    String? setDescription,
    String? createdFromTxnId,
    DateTime Function() clock = DateTime.now,
  }) async {
    final now = clock().toUtc();
    String id;
    do {
      id = 'rule_${now.microsecondsSinceEpoch}_${_ruleIdSequence++}';
    } while (await (_database.select(_database.rules)
              ..where((rule) => rule.id.equals(id)))
            .getSingleOrNull() !=
        null);
    await _database.into(_database.rules).insert(
          RulesCompanion.insert(
            id: id,
            matchType: matchType,
            matchValue: matchValue,
            setCategoryId: Value(setCategoryId),
            setDescription: Value(setDescription),
            createdFromTxnId: Value(createdFromTxnId),
            createdAt: now,
          ),
        );
    return id;
  }

  static String? _normalize(String? value) {
    final normalized =
        value == null ? null : normalizeMatchValue('counterparty', value);
    return (normalized == null || normalized.isEmpty) ? null : normalized;
  }
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final ruleRepositoryProvider = Provider.family<RuleRepository, AppDatabase>(
  (ref, database) => RuleRepository(database),
);
