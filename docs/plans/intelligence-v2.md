# Intelligence v2 — facts, timelines, explainable insights, adaptive dashboard

Status: Proposed, planning only — 2026-10-10 (T-207). Briefs:
[docs/tasks/T-207.md](../tasks/T-207.md). ADRs (Proposed):
[0034 SMS facts store](../decisions/0034-sms-facts-store.md),
[0035 dashboard layout store](../decisions/0035-dashboard-layout-store.md).

## Goal

Turn the SMS we already read into a source-faithful, explainable picture of
each account (balance, limit use, dues, mandates, investments) and surface it
through an adaptive dashboard and Ask, with the on-device model (Qwen3-0.6B,
ADR 0009) and embedder (ADR 0007) used only as advisory, background,
cache-first helpers. Deterministic extraction stays authoritative (ADR 0011);
everything is local (ADR 0002); capture never waits on a model.

## Current state (evidence)

- Template engine extracts 7 named groups only: `amount, account, date,
  merchant, vpa, ref, balance` (+ `selfvpa` in 2 templates)
  (`field_normalizer.dart:~85-110`; 37 templates in `assets/templates/*.json`).
  `balance` appears in 10 of 37 templates. Axis card regex mentions `Avl
  Limit` but does not capture it (`docs/sms-templates.md:114`).
- `NormalizedTransactionRecord` carries `balanceAfter, refId, accountHint,
  counterpartyVpa, merchantRaw` plus `FieldEvidence{field,start,end,verbatim,
  extractor}` (`normalized_transaction_record.dart:124`). Only `balance_after`,
  `ref_id`, `account_hint`, `counterparty_vpa`, `merchant_raw`, `evidence_json`
  are stored (`transactions_table.dart:46-70`).
- Generic parser (`generic_transaction_parser.dart:37-61`) extracts amount,
  account, VPA, balance, ref, date, merchant, but treats balance/limit amounts
  as exclusions (`:101-109`), not data.
- `MessageKindClassifier` knows `reminder, mandate, balance, statement`
  (`message_kind_classifier.dart:4-16`). reminder/mandate become
  `expected_events` (`sms_ingestion.dart:327`); `balance`, `statement`, `otp`,
  `promo`, `unknown` are marked processed and dropped (`:395-412`); unlinked
  raw SMS expire after 7 days (ADR 0021, `raw_sms_repository.dart:46-70`).
- `SupportingSmsClassifier` (ADR 0032) extracts due date, UTR, VPA, last-4s
  for dividend/RD/EMI/collect messages but only into link rows
  (`supporting_sms_classifier.dart:32-72`; `sms_transaction_links_table.dart`).
- `SpanVerifier` verifies `substring==verbatim` and re-parses amounts
  (`span_verifier.dart:17-52`); `LlmFieldLocator` asks the model for verbatim
  quotes and refuses re-formatted strings (`llm_field_locator.dart:10-48`).
  It is awaited inline in `ParserCascade` (`parser_cascade.dart:52`), i.e. on
  the capture path when a model exists.
- LLM runtime: `LlmRuntime.complete/extractJson` with `LlmUnavailable`
  fallback (`llm_runtime.dart:33-60`); used by Ask intent mapping with an
  in-memory intent cache (`assistant_controller.dart:30-93`) and the field
  locator. `precomputeInsights` has `TODO(T-178c)` for claim-ID selection
  (`nightly_job.dart:~101`).
- Embedder: `PlatformEmbedder` (MethodChannel `com.paisatrack/embedder`) used
  by `MerchantResolver` (suggest-only), recurring detector and nightly job.
- **Background gap:** both `LlmBridge` and `EmbedderBridge` channels are
  registered in `MainActivity.configureFlutterEngine` (`MainActivity.kt:54-64,
  290-296`). The WorkManager worker runs a headless Dart isolate
  (`nightly_job.dart:208-232`, passes `PlatformEmbedder`), so the channels are
  likely absent there and embeddings/LLM silently return null in nightly runs.
  T-207d verifies and fixes this before any background AI claim.
- Insights: `Insights(id, period, kind, payloadJson, dismissed)` with typed
  `TypedClaim{calculation, scope, window, metrics, evidenceIds, inputHash}`
  (`claim.dart:12-40`), validated by `ClaimValidator.parse` (needs `v==1`,
  `calc == kind@1`, `basis=='observed'`). Evidence ids are transaction ids.
- Dashboard: fixed `Column` of `Bloom*` widgets and ~25 Riverpod providers
  (`dashboard_screen.dart:262-301`, `dashboard_providers.dart`); no layout
  persistence. No chart package in `pubspec.yaml` (custom painters needed).
- Ask: closed intent kinds `period_total, category_breakdown, merchant_lookup,
  month_over_month, upcoming_recurring, active_insights`
  (`assistant_intent.dart:4-14`); renderer is text. Hinglish typed intents are
  T-178c (c1-c3), specified in
  [grounded-ai-validation.md](grounded-ai-validation.md) — **not duplicated
  here**; this plan only adds fact-backed intents on top of c2/c3.
- Doc drift: `docs/sms-intelligence-design.md:116` (G6) still says no store for
  expected events, but `expected_events` exists (`expected_events_table.dart`);
  `docs/decisions/README.md` index stops at ADR 0027 though 0028-0032 exist.

## Gap table: field -> template coverage -> stored? -> proposed fact

| SMS field | Template/generic coverage today | Stored today? | Proposed `sms_facts.kind` |
|---|---|---|---|
| Available/clear balance after txn | 10/37 templates (`balance`); generic `_balance` | `transactions.balance_after` only, no history | `balance_available` (+`balance_total`) |
| Standalone balance alert | none (kind `balance` dropped) | no | `balance_available` |
| Available credit limit | Axis/Kotak card text only; generic excludes as noise | no | `credit_limit_available` |
| Total credit limit | none | no | `credit_limit_total` |
| Total due / min due | none (reminder -> expected event amount only) | `expected_events.expected_amount_paise` (one amount) | `due_total`, `due_min` |
| Due date | `SupportingSmsInfo.dueDate` in memory; reminders' window | `expected_events.expected_date` | `due_date` |
| Statement date / period | none | no | `statement_date` |
| Mandate / e-mandate / AutoPay, UMN/UMRN | `indusind_upi_autopay_debit_v1` captures UMN as `ref` | only as `ref_id` | `mandate_ref`, `mandate_cap_paise`, `mandate_freq` |
| Loan a/c, EMI amount, outstanding | EMI notice link only (amount) | link row, no outstanding | `loan_account`, `emi_amount`, `loan_outstanding` |
| Interest credited | message kind filtered (`interest credit` hard reject) | no | `interest_credited` |
| MF folio / NAV / units / scheme | none | no | `mf_folio`, `mf_nav`, `mf_units`, `mf_scheme` |
| Merchant city/location | none | no | `merchant_city` |
| Card network (Visa/MC/RuPay) | none | no | `card_network` |
| Terminal / POS id | none | no | `terminal_id` |
| UPI app (GPay/PhonePe/...) | none | no | `upi_app` |
| IFSC | `indusind_neft_credit_v1` puts it in `ref` | no | `ifsc` |
| Amount, direction, date, ref, VPA, last-4, merchant | templates + generic | yes | unchanged (authoritative; not duplicated) |

## Design

### Facts (Phase 0-1)
Independent `FactExtractor` (new `lib/capture/facts/`) with pattern packs in
`assets/seed/fact_patterns_*.json` (cue + capture + kind + unit parser), run
over every non-OTP message after the raw SMS and any transaction are
persisted. It never touches the transaction parse path, so it cannot regress
capture. Every fact passes `FactVerifier` (span + re-parse, same contract as
`SpanVerifier`) before the `sms_facts` insert (ADR 0034). Conflicts (same
source+kind+day, different value) store both as `conflicted`; consumers use
none until resolved (newest `verified` wins only if one exists).
Model-located facts (Phase 7) enter through the same verifier and only for
kinds with a deterministic shape check.

### Timelines (Phase 2)
`AccountTimelineService` (read-only): balance history = `balance_available`
facts plus `transactions.balance_after`, de-duplicated by (source, instant);
utilisation = `1 - available/total_limit` only when both come from the same
SMS or within 24h, labelled "as of <time>"; due calendar = due facts merged
with `expected_events` (dedupe by source+due date). Staleness is displayed
(not hidden): >7 days shows "last SMS balance, N days ago". No cross-currency
sums (ADR 0017). These are observations, not "balance/runway promises"
(T-178 non-goal): wording always says "per last SMS".

### Explainable insights (Phase 3)
Extend the claim envelope additively with `evidence.fact_ids`
(ids of `sms_facts`) and new calcs `balance_low@1`, `limit_utilisation_high@1`,
`due_soon@1`, `balance_drop@1`. `v` stays 1; the validator accepts the new
optional key. UI "Why am I seeing this" sheet lists the evidence
transactions, fact chips (kind, value, verbatim, as-of) and, behind app lock
(T-090), the source SMS. Text is fixed templates over claim metrics.

### Adaptive dashboard (Phase 4)
Cards become registry entries (`card_type`, builder, default rank, eligibility
predicate). Layout persisted per ADR 0035; first frame uses cached layout, no
reflow after data loads (skeleton height reserved per card). Learned ranking =
decayed local tap/open counts + urgency boosts from due/low-balance claims;
user pin/reorder always wins; ranking never changes while the user is on the
screen (re-rank on next open). Edit mode: long-press -> pin, hide, drag.

### Ask charts and saved cards (Phase 5)
Deterministic `ChartSpec` (type line/bar/step, series of (x, paise), as-of,
currency, claim/result id) built from validated query results; widget is a
shared painter (T-207c). Hinglish phrasing arrives via T-178c; this plan adds
intents `account_balance`, `limit_utilisation`, `due_calendar` after c2.
"Save as dashboard card" stores the validated typed intent (ADR 0035), never
the answer text.

### Background/cached AI (Phase 6)
Rule: UI never awaits inference. `AiResultCache` stores precomputed model
selections in `insights` rows (kind prefix `ai_`, with `inputHash`);
read API returns `(value, isStale)`; stale values render immediately and a
revalidate job is requested (stale-while-revalidate). Nightly stage
`aiPrecompute` (after `precomputeInsights`) runs only if eligible (ADR 0009
gate re-checked at start, battery not low, time budget 3 min as the pipeline
`timeLimit`) and does: claim-ID selection for card captions (T-178c-c3
contract), suggested Ask prompts from the user's top intents, optional
embedder-based merchant clustering. Ineligible/unavailable -> stage skipped,
deterministic captions used. Model output is only ever a claim/result id
choice or a span quote; numbers come from claims.

### Model-assisted field location (Phase 7)
Unmatched or partly matched SMS (no fact found for a financial-looking
message) are queued by id; a background worker asks the model for verbatim
quotes of listed kinds, `FactVerifier` rechecks, fact stored as
`llm_located`, shown with a "model-found" tag. Also move the inline
`LlmFieldLocator` call out of `ParserCascade` into the same deferred queue so
capture latency is independent of the model (T-207ak).

## Constraints / invariants

- ADR 0002: no network except model download. ADR 0011: no model-set amounts,
  dates, references, SQL; silence/auto assignments are not labels; a personal
  VPA does not alone establish a non-spending transfer.
- ADR 0009: re-check RAM gate (>=4 GB total, >=1.5 GB available) at each
  background run; no model => every feature still works deterministically.
- Capture never blocks on facts or model; all new capture code is try/catch +
  flag (`facts_extraction`, default off until Phase 1 gate).
- Logging: no SMS body, VPA, account/loan/folio/UMRN, amounts or `verbatim`
  in any log; counts and kind names only (gated logger, `lib/core/logging.dart`).
- Fixtures: synthetic only, labelled per ADR 0005; do not promote trust tiers.
- Schema changes: v21 (ADR 0034) then v22 (ADR 0035); each lists migration
  test, backup/restore and delete-everything coverage. Database.dart edits are
  serialised (T-207j before T-207w).

## Data model & ADR needs

`sms_facts` (v21, ADR 0034); `dashboard_cards`, `dashboard_card_stats` (v22,
ADR 0035). AI cache reuses `insights` (no schema). Feature flags (existing
`feature_flags`): `facts_extraction`, `account_timelines`,
`dashboard_custom_layout`, `ask_charts`, `ai_background_precompute`,
`facts_llm_locator`.

## Evaluation metrics and gates

| Gate | Threshold | Task |
|---|---|---|
| Stored facts failing span verification | 0 (hard) | e,f,al |
| Fact precision on gold fixtures (per kind) | >=99%; any wrong value is a P0 | b,al |
| Fact recall on in-registry bank formats | >=90% balance/limit/due kinds; report others | b,al |
| Model-located fact precision | >=99% after verifier, recall reported separately | aj,al |
| Fact vs transaction disagreement (same SMS balance) | 0 | al |
| Ingestion overhead from extraction | p95 <=15 ms/SMS on mid-range device; backfill 10k SMS < 60 s | m,n |
| Capture unchanged | existing fixture + ingestion suites green, same outcomes | m |
| Timeline correctness | balance series equals fixture gold; utilisation only with same-instant pair | p |
| Insight numeric grounding | 100% displayed numbers resolve to claim metrics/facts | t,u |
| Dashboard first frame | no layout shift after data load; no extra frames vs T-208 baseline | z |
| Rank stability | order unchanged during a session; deterministic given counts | y |
| Cached AI | UI path performs 0 awaited inference calls (test with throwing runtime) | ai |
| Ineligible device | all features usable, `aiPrecompute` skipped | ah |
| Privacy log scan | 0 forbidden tokens in captured logs | m |
| Ask charts | chart points == query result rows exactly | ac |

Real-device evidence (owner phone): extraction stage timing, background
channel availability (T-207d), memory of nightly run; synthetic tests are not
physical acceptance (as in T-178d).

## Privacy updates (`docs/privacy.md`, task T-207m/am)

Add: facts section (what is stored, masking, retention rule from ADR 0034,
delete/backup behaviour); dashboard layout and counters are local, not backed
up counters; model processes SMS text only on-device in the background and its
output is never stored unless verbatim-verified; update "On-device language
model" to mention background/overnight runs and that downloads remain the only
network use.

## Risks

| Risk | Mitigation |
|---|---|
| Wrong fact shown as truth (e.g., balance of another account) | account resolution read-only via last-4; ambiguity -> no source link, no timeline; "as of" labels; precision gate |
| Raw-SMS growth from retention extension | newest-per-(source,kind) + 45/90-day due window (ADR 0034) |
| Background channels missing (see above) | T-207d spike first; if unsolvable, run AI only on app foreground idle |
| 0.6B model quality | advisory only; verified quotes or claim-id selection; deterministic fallback |
| Dashboard churn/flicker | cached layout first frame, reserved heights, re-rank next open |
| Overlap with T-178c, T-190, T-098, T-101, T-208 | Reference, not duplicate: c-slices own Hinglish; T-190 owns card accounting; T-101 reuses expected events (due calendar merges, does not replace); T-208 owns perf budgets |
| Pattern drift per bank | pattern packs are data; fixtures per kind; version bump supersedes facts |

## Rollout

Phase gates behind flags; Phase 1 ships dark (extraction on, no UI) for one
owner-device week to review counts via a content-free diagnostics screen
before timelines show; each later phase flag-gated, rollback = flag off.

## Open owner questions (blocking only)

1. Accept ADR 0034 retention amendment: keep one raw SMS per (account, fact
   kind) beyond 7 days (default proposed; alternative: facts only, SMS purged
   at 7 days and no re-verification)? Blocks T-207j/l.
2. Is wording "balance per last SMS (as of <date>)" acceptable given T-178's
   no-balance-promise non-goal? Default: yes, with staleness label. Blocks
   T-207ad only.

## Subtasks (details in [T-207.md](../tasks/T-207.md))

Waves are parallel groups: tasks in one group touch disjoint files and may run
concurrently once their dependencies are done. `Dep ext` = outside this plan.

| ID | Phase | Title | Size/Model | Depends | Grp |
|---|---|---|---|---|---|
| a | 0 | Field-coverage audit harness | S/Haiku | — | A |
| b | 0 | Synthetic gold-fact fixture pack | M/Sonnet | — | A |
| c | 2 | Shared chart painters | M/Sonnet | — | A |
| d | 6 | Background channel spike (Kotlin) | M/Sonnet | — | A |
| e | 1 | Fact model, kinds, verifier | M/Sonnet | — | A |
| f | 1 | Fact extractor core + pack loader | M/Sonnet | e | B |
| j | 1 | Schema v21 `sms_facts` | M/Sonnet | e, ADR 0034 accepted | B |
| ag | 6 | AiResultCache (SWR) | M/Sonnet | — | B |
| g | 1 | Patterns: balances, limits, dues, statements | M/Sonnet | f, b | C |
| h | 1 | Patterns: mandates, EMI, loans | M/Sonnet | f, b | C |
| i | 1 | Patterns: MF, interest, card/POS metadata | M/Sonnet | f, b | C |
| k | 1 | `SmsFactRepository` | M/Sonnet | j | C |
| l | 1 | Retention, backup, reset for facts | M/Sonnet | j | C |
| w | 4 | Schema v22 dashboard tables | M/Sonnet | j, ADR 0035 accepted | C |
| m | 1 | Ingestion hook, flag, privacy guard, privacy.md | M/Sonnet | f, k | D |
| n | 1 | Fact backfill nightly stage | M/Sonnet | f, k | D |
| o | 1 | Fact -> payment source resolver | S/Haiku | k | D |
| q | 2 | Due-calendar service | M/Sonnet | k | D |
| s | 3 | Claim contract: fact ids + new calcs | M/Sonnet | k | D |
| v | 3 | Transaction detail "facts" row | S/Haiku | k | D |
| x | 4 | Layout repository + card registry | M/Sonnet | w | D |
| p | 2 | Account timeline service | M/Sonnet | k, o | E |
| y | 4 | Ranker + interaction counters | M/Sonnet | x | E |
| z | 4 | Dashboard host refactor | M/Sonnet | x | E |
| ac | 5 | ChartSpec from query results | M/Sonnet | c, T-178c-c2 | E |
| aj | 7 | Background LLM fact locator | M/Sonnet | e, m, d | E |
| r | 2 | Account timeline screen + providers | M/Sonnet | p, q, c | F |
| t | 3 | Insight generators from timelines | M/Sonnet | p, q, s | F |
| aa | 4 | Dashboard edit mode UI | M/Sonnet | y, z | F |
| ab | 4 | Account cards (balance/limit/due) | M/Sonnet | p, q, z | F |
| ad | 5 | Fact intents in Ask query engine | M/Sonnet | p, q, T-178c-c2 | F |
| ae | 5 | Inline charts in Ask | M/Sonnet | ac | F |
| ak | 7 | Defer LLM field location off capture path | M/Sonnet | aj | F |
| u | 3 | "Why this" evidence sheet | M/Sonnet | s, t | G |
| af | 5 | Save Ask answer as dashboard card | M/Sonnet | ac, x, z | G |
| ah | 6 | Nightly `aiPrecompute` stage | M/Sonnet | ag, d, t, T-178c-c3 | G |
| al | 7 | Evaluation harness + gates | M/Sonnet | b, g, h, i, aj | G |
| ai | 6 | UI consumes cached AI | S/Haiku | ah, z | H |
| am | all | Docs wrap-up | S/Haiku | all | H |

Critical path: e -> j -> k -> o -> p -> t -> u / ab. Phase 0 (a, b) and the
chart widgets run immediately. Do not start any v21/v22 task until the owner
accepts the matching ADR.
