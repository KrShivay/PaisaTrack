---
name: intelligence-modules
description: >
  Use when working in lib/intelligence/ (pipeline.dart, enrichers/, models/,
  decision_policy.dart, forecaster.dart, insights_engine.dart). Use when
  adding/changing an Enricher, touching the classifier or trainer, changing
  confidence thresholds, or adding a feature to the categorizer.
checklist:
  - Every enricher implements `Enricher.enrich(TransactionRecord) ->
    Future<EnrichmentResult>` and does not write to the DB — only
    pipeline.dart commits, atomically, with the full confidence trail.
  - Confidence values follow the calibration rule: 0.9+ means "would bet
    money it's right without asking"; nothing is hardcoded to 0.9+ without
    a deterministic source (exact alias, user rule) behind it.
  - decision_policy invariants hold: nothing below the ask/silent thresholds
    is ever silently auto-applied, and the daily ask-budget
    (AppConstants.askNowDailyBudget) is checked and decremented atomically
    with sending the notification, not after.
  - New classifier features are added without breaking trainer.dart on
    existing serialized model_meta weights — a feature-set version bump
    triggers a full retrain, not a shape mismatch at inference time.
  - Every intelligence PR reports before/after metrics (auto-label rate,
    correction rate, per-category precision proxy) on the frozen eval
    fixture set in the PR description or WORKLOG entry.
  - No cloud calls anywhere in the codebase — no cloud inference path exists
    (ADR 0002). All model inference is on-device.
  - No raw SMS text reaches any enricher/classifier input — only
    normalized fields (merchant_canonical, amount_band, channel).
  - Rules (user-taught) always win over the classifier — verified by a
    table-driven test, not just code inspection.
---

# Intelligence Modules Conventions

Plan references: PLAN.md §7 (full intelligence design), §4 (Intelligence
feature list, phased), §6.1 (`feedback`, `baselines`, `model_meta` tables).

## 1. The Enricher interface contract

```dart
abstract class Enricher {
  Future<EnrichmentResult> enrich(TransactionRecord txn);
}

class EnrichmentResult {
  const EnrichmentResult({
    required this.field,
    required this.value,
    required this.confidence,
    required this.source,
  });

  final String field;       // 'merchant' | 'category' | ...
  final Object? value;
  final double confidence;  // 0.0–1.0
  final String source;      // 'alias' | 'rule' | 'classifier' | 'seed' | 'llm'
}
```

An enricher **reads** the transaction and the repositories it needs (merchant
table, rule table, model weights) and **returns** a result — it never calls
`db.update(...)` itself. `pipeline.dart` is the only place that assembles
results from `merchant_resolver → categorizer → (async: recurring_detector,
anomaly_detector)` into the confidence trail and commits in one DB
transaction, then hands off to `decision_policy`. This is what keeps the
confidence trail complete and auditable — if enrichers wrote independently,
a partial failure could leave a transaction half-enriched with no record of
why.

## 2. Confidence semantics — what a number must mean

Confidence is not a vibe. Calibration expectations by source, per plan §7.3/§7.4:

| Source | Confidence | Meaning |
|---|---|---|
| Exact alias / user rule | 1.0 | Deterministic, no uncertainty — this is not a prediction. |
| Embedding auto-link | ≥0.92 | Cosine similarity band the plan defines as safe to auto-link. |
| Embedding review band | 0.75–0.92 | Link but mark `needs_review` — never silent. |
| Local classifier | softmax top-prob | Only "used" if ≥ that category's threshold in `model_meta`; a 0.95 the policy doesn't trust is still just a number, not an auto-apply. |
| Seed map | 0.8 (fixed) | A prior, not a measurement — never let it silently outrank a real classifier once one exists. |
| LLM zero-shot (flagged) | capped 0.75 | Never allowed to reach silent-auto territory alone — plan explicitly caps it. |
| No signal | 0.3, category `Other` | Guaranteed to enter ask/batch — this is the safety net, don't "fix" it by raising the floor. |

If you're adding a new source, decide which band it belongs in *before*
writing the enricher, and write that decision into the enricher's doc
comment — a reviewer should never have to reverse-engineer what a
confidence number is supposed to mean.

## 3. Decision policy invariants

```
c = min(merchant.c, category.c)
c >= silent_threshold(category)                         -> 'auto'
c >= 0.6 and (amount >= 500 or merchant.txn_count >= 3)
    and ask_budget_left                                  -> 'asked'
else                                                      -> 'needs_review'
new P2P counterparty                                      -> always ask once
```

Invariants to defend in code and in review:
- **Never silent below threshold.** There is no code path where a
  transaction below `silent_threshold(category)` gets `status = 'auto'`.
  If you're tempted to add one "just for this special case," it's a new
  named rule in the rules table, not a policy exception.
- **Ask-budget respected.** `askNowDailyBudget` (constants.dart) is checked
  and decremented as one atomic operation with actually sending the
  notification — a race where two transactions both see "budget left" and
  both fire is a bug, not an edge case to shrug off.
- **New counterparty always asks once**, regardless of confidence — this
  is how a rule gets created from the answer (plan §4 Learning Loop). Don't
  let a high classifier confidence skip this for a first-time payee.
- Adaptive thresholds (P3, plan §7.5): only adjust
  `model_meta` per-category thresholds via the nightly job, in the
  documented direction (+0.03 capped 0.98 on >15% correction rate over
  trailing 50; -0.01 per clean 50) — no ad hoc threshold nudges from other
  code paths.

## 4. Adding features to the classifier without breaking the trainer

`classifier.dart` (pure Dart logistic regression) and `trainer.dart`
(nightly retrain from `feedback`) share an implicit feature vector shape.
When adding a feature (plan §4 lists: merchant embedding, log-amount-band,
hour-bucket, dow, channel):

1. Bump a `featureSetVersion` constant alongside the feature extraction
   function.
2. `model_meta` stores the `featureSetVersion` the current weights were
   trained with. `trainer.dart` retrains from scratch (not incrementally)
   whenever the running feature version doesn't match — never feed a
   longer/shorter feature vector into weights sized for a different
   version.
3. Add a property test (see `testing-discipline`) asserting the trainer
   doesn't crash when feedback rows predate the new feature (backfill a
   sane default, e.g. 0 or the feature's neutral value).

## 5. Evaluation harness — every intelligence PR reports metrics

There is a frozen eval fixture set (transactions + known-correct
labels) that every classifier/policy change is measured against.
Before/after numbers — auto-label rate, correction rate, and per-category
precision proxy — go in the PR description and the WORKLOG entry. A PR
that changes thresholds, features, or the classifier without these numbers
is not reviewable; `code-review` should send it back with CHANGES.

## 6. Do-not list

- No cloud calls from anywhere in the codebase — no cloud inference path
  exists (ADR 0002). LLM use is on-device only: `lib/capture/llm_extractor.dart`
  (parsing fallback) and a narrative-insight path (P4, flagged), gated behind
  `AppConstants.enableLocalLlm` / `enableNarrativeInsights`. The narrative
  path operates on aggregate data only, never raw SMS.
- No raw SMS text into any enricher or classifier input. Enrichers and
  the classifier operate on `NormalizedTransactionRecord` fields
  (`merchant_raw`/`merchant_canonical`, amount band, channel) — never
  `RawSms.body`. (The on-device `llm_extractor` in `lib/capture/` is the
  sole component that may see raw SMS, since inference never leaves the
  device.)
- No enricher silently overrides a user rule. Rules win, full stop —
  table-driven test required (see `testing-discipline`).

## Related

- `db-and-migrations` — `feedback`, `baselines`, `model_meta` schemas.
- `flutter-conventions` — Enricher injection via Riverpod providers.
- `testing-discipline` — eval harness, table-driven decision-policy tests.

Also see: `lib/intelligence/AGENTS.md`, which restates the eval-metric
requirement directly inside this directory for any agent editing here.
