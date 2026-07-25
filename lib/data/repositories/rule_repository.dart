import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';

/// User-taught deterministic rules — step 1 of the categorizer ladder
/// (PLAN §7.4). Rules always win over probabilistic enrichment.
class RuleRepository {
  const RuleRepository(this._database);

  final AppDatabase _database;

  /// First rule matching the transaction's signals, or null.
  ///
  /// `counterparty` rules (exact VPA identity) are checked before `merchant`
  /// rules (normalized substring of the merchant text), since an exact
  /// identity is the stronger signal. Unknown match_types never match.
  Future<Rule?> findMatch({
    String? merchantRaw,
    String? counterpartyVpa,
  }) async {
    final rules = await _database.select(_database.rules).get();

    final vpa = _normalize(counterpartyVpa);
    if (vpa != null) {
      for (final rule in rules) {
        if (rule.matchType == 'counterparty' &&
            _normalize(rule.matchValue) == vpa) {
          return rule;
        }
      }
    }

    final merchant = _normalize(merchantRaw);
    if (merchant != null) {
      for (final rule in rules) {
        final value = _normalize(rule.matchValue);
        if (rule.matchType == 'merchant' && value != null) {
          final pattern =
              RegExp(r'\b' + RegExp.escape(value) + r'\b', caseSensitive: false);
          if (pattern.hasMatch(merchant)) {
            return rule;
          }
        }
      }
    }

    return null;
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
    final id = 'rule_${now.microsecondsSinceEpoch}';
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
    final normalized = value?.toLowerCase().trim();
    return (normalized == null || normalized.isEmpty) ? null : normalized;
  }
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final ruleRepositoryProvider = Provider.family<RuleRepository, AppDatabase>(
  (ref, database) => RuleRepository(database),
);
