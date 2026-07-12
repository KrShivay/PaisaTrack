# Task Board
Last updated: 2026-07-12 by @codex (T-051/T-052/T-053/T-054/T-062/T-063 tested and submitted for @claude review.)

## In Progress          <!-- max 1 task per agent at a time -->

## Ready                <!-- groomed, unambiguous AC, ordered by priority -->
<!-- 2026-07-12 @claude (@human-directed): T-051 + T-052 pulled into Ready to give @codex
     a live execution runway — both depend only on Done work (T-048/T-049/T-050). T-051
     (merchant resolver) is the Phase 3 critical-path head; T-052 (classifier) is
     parallel-safe (separate files) but T-051 leads by queue order. Owners @codex build /
     @claude review; the Phase 3 exit (T-064) stays @claude. Note: these carry no per-task
     Model line, so the dispatcher uses CLI defaults — set one if a specific tier is wanted. -->
## Phase 3 — Intelligence (groomed backlog; gated on the Phase 2.5b trust loop T-072..T-074, cleared 2026-07-11; remaining items still blocked on T-050 or same-phase deps)
<!-- PLAN §7 (implementation), §4 [P3] inventory, §9 Phase 3 exit criteria. Do NOT
     start until T-046 → Done (commit unblocked + canonical device test green).
     Dependency-ordered; schema v3 (T-048, now in Ready) unblocks the analytics
     chain, embedder (T-050) unblocks resolver/classifier. Owners provisional
     (@codex build / @claude review) per COLLABORATION.md; the exit review
     (T-064) is @claude. -->
- [ ] T-061 (@codex) [P3] Nightly job orchestrator (WorkManager)
      AC: PLAN §7.9 pipeline in order — purge expired raw_sms → recurring scan → baselines → retrain (if ≥30 new feedback) → recompute thresholds → precompute insights; WorkManager constraints device idle + charging, hard cap 3 min, resumable/checkpointed; single run wires the whole nightly batch; integration test over a seeded DB asserts each stage ran and is resumable.
      Depends: T-053, T-055, T-057, T-058, T-059
- [ ] T-064 (@claude) [P3] Phase 3 exit review
      AC: verifies PLAN §9 Phase 3 exit criteria against T-048..T-063 evidence — after 2 weeks of feedback the classifier auto-labels ≥80% of new transactions with ≤10% correction rate (proven on the T-062 metrics screen); real subscriptions/EMIs all appear in recurring with correct next dates; ≥1 genuine anomaly and ≥1 forecast insight have fired correctly; WORKLOG "PHASE P3 EXIT REVIEW"; blockers listed before Phase 4 grooming.

## Phase 4 — Assistant & LLM layer (groomed; gated on Phase 3 exit T-064 + T-075; ADR 0006)
- [ ] T-076 (@codex) [P4] In-app assistant: ask your money anything
      AC: chat surface behind the LLM feature flag; NL question → LLM emits constrained intent JSON (metric, category/merchant filter, time range, aggregation) validated against a whitelist — model NEVER emits SQL; deterministic QueryEngine executes intents over repositories (transactions, recurring_series, baselines, insights); reply interpolates ONLY QueryEngine numbers (renderer test proves no model-originated figures); out-of-whitelist intents refuse gracefully with suggestions; no advice framing — forecasts relay PLAN §7.8 outputs only; session-scoped history; prompts never leave the device (ADR 0002/0006). MVP intents: period totals, category breakdown, merchant lookup, month-over-month comparison, upcoming recurring, active insights.
      Spec: implement to docs/assistant-nlq.md (T-083, @claude) — the intent schema, whitelist, and grounding contract are defined there, not invented here; do NOT start the build until T-083 is Done.
      Model: gpt-5.6-sol medium
      Depends: T-083 (spec, Done), T-075 (LLM runtime, In Progress — Review: CHANGES), T-064 (Phase 3 exit)

## Blocked
- [ ] T-067 (@claude fixtures → @codex templates) [P2] Kotak + Central Bank template packs (public provenance)
      AC: @claude gathers >=10 real publicly-posted transactional SMS per bank (forums/parser repos; verbatim, source-noted, no fabrication) into test/fixtures/sms/{kotak,centbk}/ with `"provenance": "public"` and hand-computed expected JSON; @codex authors template packs; per-bank coverage test includes both banks; templates carry public provenance (capped 0.85 via T-072); docs/sms-templates.md updated.
      Blocking: needs T-072 landed first; fixture-gathering is @claude In Progress work
## Backlog (ungroomed)
<!-- 2026-07-12 @claude: the three T-071 donation-sanitizer follow-ups were groomed into
     Ready and renumbered T-080/T-081/T-082 — they had been mis-logged as T-077/T-078/T-079,
     colliding with the already-completed T-077 (Save exports) and T-078 (Weekly review).
     ID T-079 is retired and left unused rather than reassigned, per the never-reuse rule. -->
<!-- (empty) -->

## In Review

- [ ] T-051 (@codex → review @claude) [P3] Merchant resolver v2 (embedding similarity)
      AC: PLAN §7.3 — exact alias lookup (1.0) → brute-force cosine similarity vs stored merchant embeddings (<2k merchants): ≥0.92 auto-link + write `learned` alias; 0.75–0.92 link with `needs_review` mark; <0.75 create+embed new merchant. Slots ahead of the categorizer in the enrichment pipeline (§7.2); writes `merchant` block into the confidence trail (T-049); tests for each band + alias promotion.
      Depends: T-050, T-049 (both Done)
      Evidence: test/enrichment/merchant_resolver_test.dart covers exact-alias(1.0), auto-link(≥0.92, `learned` alias), review-band(0.75–0.92, `similarity` alias + `needsReview`), below-band(new merchant+embed), no-embedder fallback, VPA fallback, `normalizeAlias`, and `cosineSimilarity` edge cases (identical/orthogonal/mismatched-length/zero-vector).
- [ ] T-052 (@codex → review @claude) [P3] Local classifier + categorizer ladder step 2
      AC: pure-Dart softmax/logistic classifier (no heavy deps per §2) over features = merchant embedding (or top-N merchant one-hot) + log-amount band + hour bucket + dow + channel; loads weights from `model_meta`; wired as ladder step 2 (PLAN §7.4) between rules(1.0) and seed(0.8), used only when top-prob ≥ per-category threshold; no-model → ladder falls through unchanged; inference + feature-extraction tests.
      Note (2026-07-10): also cover fuzzy/free-text category resolution for ask-now answers — typo'd free text currently lands 'Other' silently (see T-044). Not addressed in this pass — still open.
      Depends: T-048, T-050 (both Done)
      Evidence: test/enrichment/local_classifier_test.dart covers `features()` padding/truncation/zero-fill and the exact log-amount/hour/dow/channel encoding, `ClassifierModel` JSON round-trip and malformed/shape-mismatch rejection, `predict()` no-model and malformed-model no-ops, softmax category selection, and a feature-vector/weight-shape mismatch returning null.
- [ ] T-053 (@codex → review @claude) [P3] Nightly classifier trainer
      AC: trains the T-052 classifier on `feedback` rows (retrain trigger ≥30 new feedback rows per §7.9); persists weights + `last_trained_at` + version to `model_meta`; pure-Dart, bounded runtime; deterministic-seed training test asserting improved fit on a fixture feedback set; no raw SMS in features.
      Depends: T-052
      Note: implemented as `ClassifierTrainer` inside lib/enrichment/local_classifier.dart rather than a separate trainer.dart file.
      Evidence: test/enrichment/local_classifier_test.dart `ClassifierTrainer` group covers empty-feedback no-op, <2-category no-op, a successful train persisting `classifier_v1` + `classifier_last_trained_at`, non-category_id feedback rows being ignored, and same-seed determinism (two trains on identical data produce byte-identical `model_meta`).
- [ ] T-054 (@codex → review @claude) [P3] Decision policy v2 (adaptive thresholds)
      AC: per-category silent thresholds persisted in `model_meta`; PLAN §7.5 adaptation — corrections/auto-labels >15% over trailing 50 in a category → raise threshold +0.03 (cap 0.98); each clean 50 → lower 0.01; policy reads per-category threshold instead of the static constant; back-compat default when no history; branch tests for raise/lower/cap/floor.
      Depends: T-052, T-040
      Evidence: test/enrichment/decision_policy_test.dart `AdaptiveThresholdPolicy` group covers null/missing/malformed-history defaults, <50-recent skip, +0.03 raise at >15% correction rate, -0.01 lower on a clean trailing 50, and the 0.98 cap / 0.0 floor clamps.
- [ ] T-062 (@codex → review @claude) [P3] Model metrics dev screen (hidden)
      AC: classifier accuracy on the last 100 feedback items, ask-rate, and per-category correction-rate from `feedback` + confidence trail (T-049); hidden/dev-only entry like the unparsed screen; this screen is the evidence surface for the Phase 3 exit criterion; widget test over seeded metrics.
      Depends: T-052, T-054
      Evidence: test/features/dev/model_metrics_screen_test.dart covers `ModelMetricsRepository.load` (zeroed empty state, accuracy/ask-rate/per-category correction-rate computation, non-category_id feedback ignored, most-recent-100 window) and a `ModelMetricsScreen` widget test for the rendered data + error state.
- [ ] T-063 (@codex → review @claude) [P3] Learning loop: correction → rule + training example + alias (one write)
      AC: PLAN §4 [P3] — extend `correctWithRule` so a single DB transaction stages the rule (existing), a training example for the classifier, and a learned merchant alias when the correction implies one; all commit/roll back together; no double-apply; transaction test over the combined write.
      Depends: T-051, T-052
      Note: the category-feedback row already doubles as the classifier training example (consumed by `ClassifierTrainer`); this task's addition is the learned merchant alias write inside the same DB transaction.
      Evidence: test/data/repositories/transaction_repository_test.dart covers the learned-alias write when the transaction is resolver-linked, the no-op when unlinked or `merchantRaw` is absent, the alias committing atomically alongside the rule/feedback/status update, and upsert (no duplicate) on a repeat correction of the same normalized alias.
- [ ] T-075 (@codex → review @claude) [P4] On-device LLM runtime foundation
      AC: shared feature-flagged `LlmRuntime` using ADR 0008's pinned MediaPipe model; resumable, integrity-checked app-private download with Settings delete; typed no-op fallback; offline inference; strict JSON extraction; and Phase 4/privacy documentation. Serves the extractor, narratives, and T-076.
      Model: gpt-5.6-terra high
      Depends: T-074 (Done; queue order only — Phase-3-parallel safe)
      Pin: docs/decisions/0008-on-device-llm-model.md
      Evidence: fixed full-size partial promotion before HTTP Range (native valid/corrupt regressions); cached native inference is closed during Flutter-engine cleanup (native release regression); schema `enum` validation retries then rejects invalid values (Dart regressions). GitNexus pre-edit impacts LOW: `PlatformLlmRuntime` 4 direct/6 total/1 test process; `LlmBridge` 1 direct; `MainActivity` 0. `flutter analyze --no-pub` clean; focused Flutter 10/10; full Flutter 218/218; focused Android `LlmBridgeTest` BUILD SUCCESSFUL; `git diff --check` clean. Final detect_changes HIGH is coarse: it combines the concurrent TASKS archive compaction with the broad MainActivity class; affected implementation paths are the expected download/complete/delete/platform-channel flows.

## Done                 <!-- move here only after review passes; keep last 20, archive rest to docs/tasks-archive.md -->
<!-- One-line verdicts only; full review notes live in docs/tasks-archive.md and WORKLOG.md. -->
- [x] T-083 (@claude build / @codex review: PASS) [P4] Spec: in-app assistant NLQ grounding contract (2026-07-12)
- [x] T-080/T-081/T-082 (@claude build / @codex review: PASS) [P2/P3] Donation sanitizer hardening (2026-07-12)
- [x] T-071 (@codex implemented 2026-07-11; review @claude: PASS) [P2] In-app sanitized SMS donation flow (unparsed screen) (2026-07-11)
- [x] T-050 (@claude, verification/review @codex: PASS) [P3] On-device text embedder (2026-07-11)
- [x] T-060 (@codex, review @claude: PASS) [P3] Insights screen (2026-07-11)
- [x] T-059 (@codex, review @claude: PASS) [P3] Deterministic insights engine (2026-07-11)
- [x] T-056 (@codex, review @claude: PASS) [P3] Recurring screen (2026-07-11)
- [x] T-058 (@codex, review @claude: PASS) [P3] Burn-rate forecaster (2026-07-11)
- [x] T-070 (@claude, review @claude: PASS) [P2] Unparsed screen: per-stage generic rejection reason (2026-07-11)
- [x] T-018 (@claude, review @claude: PASS) [P0] CI generated-code and build_runner guards (2026-07-11)
- [x] T-057 (@codex, review @claude: PASS) [P3] Anomaly detector (nightly baselines) (2026-07-11)
- [x] T-055 (@codex, review @claude: PASS) [P3] Recurring detector (nightly batch) (2026-07-11)
- [x] T-049 (@codex, review @claude: PASS) [P3] Confidence trail per transaction (2026-07-11)
- [x] T-078 (@codex, review @claude: PASS) [P2] Weekly review: bulk confirm + merchant grouping (2026-07-11)
- [x] T-077 (@codex, review @claude: PASS) [P2] Save exports via system file picker (user-visible destination) (2026-07-11)
- [x] T-074 (@codex, review @claude: PASS) [P2] Template trust ledger + promotion/demotion (2026-07-10)
- [x] T-048 (@codex, review @claude: PASS) [P3] Schema v3 migration (analytics tables) (2026-07-10)
- [x] T-073 (@codex, review @claude: PASS) [P2] Parse-confirmation surface + verdict feedback (2026-07-10)
- [x] T-072 (@codex, review @claude: PASS) [P2] Provenance-capped template confidence (2026-07-10)
- [x] T-069 (@codex, review @claude: PASS) [P2] Unparsed dev screen shows rejection stage (2026-07-10)

## Proposed
