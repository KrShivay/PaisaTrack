import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database_provider.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/repositories/rule_repository.dart';
import 'seed_category_map.dart';

/// Outcome of one categorizer ladder run (PLAN §7.4).
class CategorizationResult {
  const CategorizationResult({
    required this.categoryId,
    required this.confidence,
    required this.source,
    this.ruleId,
  });

  /// Never null: the ladder bottoms out at `other`.
  final String categoryId;
  final double confidence;

  /// `'rule'`, `'seed'`, or `'fallback'` — recorded in `confidence_json`.
  final String source;

  /// Set when a user-taught rule decided the category.
  final String? ruleId;
}

/// Categorizer ladder, steps 1 + 3 for Phase 2 (PLAN §7.4):
/// rules (confidence 1.0) → seed map (0.8) → `other` (0.3, guaranteed to
/// enter the ask/batch flow once the decision policy lands, T-040).
///
/// The classifier (step 2) and on-device LLM (step 4) are later phases and
/// slot between these without changing the contract.
class Categorizer {
  const Categorizer({
    required RuleRepository rules,
    required SeedCategoryMap seedMap,
  })  : _rules = rules,
        _seedMap = seedMap;

  static const seedConfidence = 0.8;
  static const fallbackConfidence = 0.3;
  static const fallbackCategoryId = 'other';

  final RuleRepository _rules;
  final SeedCategoryMap _seedMap;

  /// Runs the ladder for one parsed record. Rules always win.
  Future<CategorizationResult> categorize(
    NormalizedTransactionRecord record,
  ) async {
    final rule = await _rules.findMatch(
      merchantRaw: record.merchantRaw,
      counterpartyVpa: record.counterpartyVpa,
    );
    if (rule?.setCategoryId != null) {
      return CategorizationResult(
        categoryId: rule!.setCategoryId!,
        confidence: 1.0,
        source: 'rule',
        ruleId: rule.id,
      );
    }

    final seeded = _seedMap.categoryFor(record.merchantRaw) ??
        _seedMap.categoryFor(record.counterpartyVpa);
    if (seeded != null) {
      return CategorizationResult(
        categoryId: seeded,
        confidence: seedConfidence,
        source: 'seed',
      );
    }

    return const CategorizationResult(
      categoryId: fallbackCategoryId,
      confidence: fallbackConfidence,
      source: 'fallback',
    );
  }
}

/// Bundled seed map, loaded once per app run.
final seedCategoryMapProvider = FutureProvider<SeedCategoryMap>((ref) async {
  final source = await rootBundle.loadString('assets/seed/category_seed.json');
  return SeedCategoryMap.fromJson(source);
});

/// Categorizer for the live/backfill ingest pipelines. Resolves once the
/// database and the bundled seed map are ready.
final categorizerProvider = FutureProvider<Categorizer>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final seedMap = await ref.watch(seedCategoryMapProvider.future);
  return Categorizer(
    rules: ref.watch(ruleRepositoryProvider(database)),
    seedMap: seedMap,
  );
});
