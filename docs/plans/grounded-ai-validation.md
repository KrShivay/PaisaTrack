# Grounded AI validation plan

Status: proposed. This plan breaks T-178b–d into groomable implementation
slices; it does not approve a model, schema migration, rollout, or release.
T-178a is complete and supplies the shared evidence and coverage semantics.
See [T-178](../tasks/T-178.md), the [AI opportunities report](../reports/grounded-ai-opportunities.md), and [ADR 0011](../decisions/0011-evidence-backed-assistance.md).

## Current state

- `TypedClaim` is a versioned observed-fact envelope with scope, window,
  numeric metrics, evidence IDs/count, input hash, and raw payload. The strict
  v1 parser currently accepts `category_delta`, `fees_total`, `price_creep`,
  `duplicate_subscription`, and `missed_autopay`; unknown kinds and additional
  fields fail closed. See [`TypedClaim` and `ClaimValidator`](../../lib/intelligence/claim.dart#L11)
  and the exact shape list in [`_validShape`](../../lib/intelligence/claim.dart#L166).
- `freshClaims` reparses claims, rereads transaction/category rows, checks
  evidence IDs, count, hash, eligibility and calculation freshness, then sorts
  the survivors. `ClaimRenderer` uses fixed templates and ignores payload prose.
  See [`ClaimValidator.isFresh`](../../lib/intelligence/claim.dart#L254),
  [`freshClaims`](../../lib/intelligence/claim.dart#L457), and
  [`ClaimRenderer`](../../lib/intelligence/claim.dart#L558).
- The former point forecast still exists in `BurnRateForecaster`: it sums the
  current month with per-day medians from three trailing months, and writes a
  raw `forecast` insight when the deviation exceeds its threshold. The
  `AnomalyDetector` also persists anomaly rows. Nightly work still calls both
  paths through `DerivedReadsService`. See
  [`BurnRateForecaster.run`](../../lib/intelligence/burn_rate_forecaster.dart#L32),
  [`AnomalyDetector`](../../lib/intelligence/anomaly_detector.dart#L1), and
  [`NightlyPipeline.production`](../../lib/intelligence/nightly_job.dart#L59).
- T-178a's user-facing claim path hides those legacy forecast/anomaly rows:
  their kinds are not in `ClaimValidator`'s accepted shapes, and Ask reads only
  fresh validated claims. The query-engine regression test verifies raw
  forecast, anomaly, and model-authored insight rows do not surface. This is
  suppression at the validated display boundary; it does not mean the legacy
  calculations or nightly writes were deleted. See
  [`AssistantQueryEngine._insights`](../../lib/intelligence/assistant/query_engine.dart#L859)
  and [`query_engine_test.dart`](../../test/intelligence/assistant/query_engine_test.dart#L837).
- Ask tries the local deterministic classifier first; if it cannot classify,
  it requests a compact structured intent from the on-device runtime. The
  result passes `IntentValidator`, then `AssistantQueryEngine`, then the fixed
  `AnswerRenderer`. Common supported intents bypass the model. Model output
  never supplies answer prose or figures. See
  [`AssistantController.ask`](../../lib/intelligence/assistant/assistant_controller.dart#L34),
  [`AssistantIntentClassifier`](../../lib/intelligence/assistant/assistant_intent_classifier.dart#L3),
  [`IntentValidator`](../../lib/intelligence/assistant/assistant_intent.dart#L151),
  [`AssistantQueryEngine.run`](../../lib/intelligence/assistant/query_engine.dart#L168),
  and [`AnswerRenderer`](../../lib/intelligence/assistant/answer_renderer.dart#L5).
- Existing intents include period totals, category breakdowns, period
  comparisons, recurring payments, and active insights. Current intent
  validation and prompt-catalogue tests are useful regression seeds, not a
  Hinglish evaluation corpus. See [`AssistantIntentKind`](../../lib/intelligence/assistant/assistant_intent.dart#L3),
  [`prompt_catalogue.dart`](../../lib/intelligence/assistant/prompt_catalogue.dart#L22),
  and [`assistant_intent_classifier_test.dart`](../../test/intelligence/assistant/assistant_intent_classifier_test.dart#L1).
- Settled-spending eligibility is centralized: settled, non-deleted,
  non-duplicate, not analytics-excluded, not an owned transfer, debit, and
  spending category. Credits (including unlinked refunds) are not debit spend.
  Source currency is retained in claim scope/buckets; calculations must not
  add unlike currencies. See [`FinancialEligibility`](../../lib/data/analytics/financial_eligibility.dart#L5),
  [`ClaimEvidenceScope`](../../lib/intelligence/claim.dart#L393), and
  [`source_currency.dart`](../../lib/data/models/source_currency.dart).

The above describes the inspected worktree. GitNexus was queried against the
main checkout index as requested, but its index is 16 commits behind this
worktree; its flow results are advisory and were not used as evidence for
current behavior. Source and tests linked above are the evidence.

## T-178b — Forecast ranges and backtesting

**Goal / scope:** validate a forecast interval for recorded eligible spending,
then surface only versioned, fresh forecast and anomaly claims that pass the
evidence and calibration gates below. **Non-goals:** predicting account
balances, inventing missed transactions, or changing recurring-series state.

### Candidate methods and recommendation

| Method | Strength | Limitation | Plan |
|---|---|---|---|
| Historical month-to-date ratio quantiles | Directly estimates the remaining-month multiplier from earlier months at the same elapsed day; produces an empirical interval. | Requires complete, comparable monthly history and positive month-to-date amounts; unusual early-month transactions can widen the range. | **Recommended first candidate.** Use only complete eligible months, bucket origins by elapsed-day fraction, and report the number of usable origins. |
| Seasonal-naive month estimate | Easy-to-explain baseline; low implementation cost. | Same-month-of-year history is sparse for new users and does not adapt to changed habits. | Mandatory benchmark where sufficient history exists; also benchmark the current three-month day-median method. |
| Recurring commitments plus discretionary residual | Can expose known upcoming commitments separately. | Series can be missed or stale; a recurring charge already present in month-to-date spend can be counted twice. | Evaluate only as a later candidate. Require an explicit included-commitment set and subtract observed occurrences before adding future ones. |

For each historical origin, calculate eligible cumulative spend through the
same elapsed-day fraction and final eligible spend for that complete month.
The empirical distribution of `final / month_to_date` supplies low, median,
and high multipliers; apply them to current month-to-date spend. Candidate
interval: empirical 10th–90th percentiles (nominal 80% coverage); point
estimate: median. Compare against the seasonal-naive and existing three-month
day-median baselines at both 7-day and month-end horizons. This is a proposal,
not a selected production algorithm; if history cannot support quantiles,
abstain instead of fabricating a range.

### Coverage and claim contract

- Calendar boundaries use `FinancialCalendar`; all model and evaluation
  snapshots use only information known at the forecast origin. The output says
  “recorded eligible spending” and does not imply total real-world spending,
  available cash, savings, affordability, or account balance.
- Candidate sufficiency floor: at least 6 complete prior months, with at least
  15 eligible debit transactions in each month used; current month has at least
  7 elapsed days and 10 eligible debit transactions. Require at least 20
  comparable historical month-to-date origins for an 80% empirical range.
  Six months yield only six origins at one exact elapsed day, so the 20-origin
  floor implies pooling origins within a ±3 elapsed-day window. Pooled origins
  from one month are correlated: count effective sample size by month, compute
  confidence intervals with a month-block bootstrap, and treat the 20-origin
  floor as a pooled-origin count, not independent evidence.
  These are proposed starting cutoffs: sweep thresholds in synthetic tests and
  retain only those that meet error and coverage gates without hiding most
  otherwise eligible accounts.
- Use `FinancialEligibility.spendingDebit` as the row inclusion rule. Exclude
  pending/non-settled, deleted, duplicate, analytics-excluded, owned-transfer,
  non-spending-category, and credit rows. Treat linked refund accounting only
  according to the verified refund contract; do not subtract an unlinked credit
  from debit spend. Do not assume an unobserved day is a zero-capture day.
- Keep source-currency buckets separate. Do not convert foreign-currency
  values. Each range is for one currency bucket; mixed-currency history either
  receives separate per-currency claims or abstains if the UX cannot explain
  them.
- Add a versioned forecast claim shape with central estimate, lower/upper
  values, currency, forecast origin and target window, `method_version`,
  `nominal_coverage`, history-month/origin counts, current eligible transaction
  count, coverage limitation codes, and sorted evidence IDs/input hash. The
  forecast is explicitly a prediction, not an observed claim; give it a
  distinct `basis` and validator path rather than weakening `basis: observed`
  for existing claims. Evidence includes the current-period eligible rows and
  enough stable historical period identifiers to reproduce the selected
  training origins. T-178a confirmed the current insight envelope supports
  claims without a schema migration; add one only if later measured requirements
  cannot fit the existing payload.
- Suppress if any sufficiency floor fails, the input hash is stale, currency
  buckets are mixed, interval is non-finite or inverted, the central estimate
  falls outside the interval, known history gaps exceed the coverage rule, or
  the model is outside the tested history/day bucket. Include a concise
  suppression reason for evaluation; do not render a partial numeric forecast.

### Backtest and gates

Use rolling-origin splits over synthetic ledgers and an owner-local evaluation
run. At each origin, exclude all later transactions and corrections; score
actual recorded eligible month-end totals. Include 7-day and month-end horizons,
new/long-history accounts, irregular totals, missing capture periods, changed
habits, zero/low month-to-date spend, large single synthetic purchases,
refunds, transfers, non-spending categories, month lengths, and multiple
currencies. Never random-split transaction rows. The owner-local run executes
on-device; raw dates, transactions, amounts, payees, IDs, and row-level
predictions stay there. Only aggregate metric counts/values may leave after
explicit owner export; suppress tiny cohort breakdowns that could expose an
individual account.

Proposed release gates (report sample count and bootstrap 95% confidence
intervals; thresholds apply to supported cohort and horizon, not pooled only):

| Metric | Pass threshold |
|---|---|
| Empirical 80% interval coverage | 75–88% in aggregate; no reported history-length bucket below 70% or above 92%. |
| Point error | MdAPE ≤25% on non-zero actuals; publish MAPE as a secondary metric and report zero/near-zero actuals separately. |
| Pinball loss | Median and 10th/90th quantile pinball loss each no worse than the better supported seasonal-naive/current-method baseline. |
| Interval usefulness | Median interval width / actual ≤1.0 on non-zero outcomes; report alongside coverage so an always-wide range cannot pass alone. |
| Suppression | ≤60% of otherwise eligible origins, with every failure reason counted. Higher suppression blocks release pending a product decision, even if covered cases score well. |
| Reproducibility | Same frozen synthetic ledger, origin, and method version returns identical claim payload and evidence hash. |

**Anomaly claims:** retain candidate scoring separate from user-facing claims
until evaluated. Inject labeled anomalies into synthetic baselines across
currency, category, history length, and transaction magnitude. Pass only with
precision ≥90%, recall ≥80%, and no more than 1 false alert per synthetic
account-month; report precision/recall by history bucket and alert suppression
rate. Validate owner-local false-alert burden without exporting row data.
Suppress claims when the minimum comparable periods or transactions are absent,
the eligible baseline is stale, or a source/currency scope is ambiguous. A
synthetic injected anomaly score is not physical or owner-data acceptance.

### T-178b slices

| Slice | Goal and acceptance evidence | Dependencies / files likely touched | Privacy, rollback, size |
|---|---|---|---|
| **b1 — Forecast contract and model comparison** | Define origin, horizons, claim fields, sufficiency, suppression, and baselines. Run `flutter test test/intelligence/forecast_backtest_test.dart test/intelligence/burn_rate_forecaster_test.dart`; fixtures prove no future leakage and deterministic method versions. | T-178a coverage/eligibility; `burn_rate_forecaster.dart`, `claim.dart`, `financial_eligibility.dart`; likely add `test/intelligence/forecast_backtest_test.dart`. | Synthetic only. Revert candidate algorithm/shape; **~M**. |
| **b2 — Rolling-origin evaluator** | Run `dart run tool/forecast_eval.dart --synthetic`; run `dart run tool/forecast_eval.dart --owner-local --aggregate-only` only on the owner's device. Emit aggregate coverage, error, pinball, width, and suppression metrics; all listed gates are reproducible. | b1; T-177a holdout/coverage contract; T-177f measurement plumbing; likely evaluator under `tool/` and test fixtures. | Raw owner rows remain on-device; export aggregates only. Remove evaluator without affecting runtime; **~M**. |
| **b3 — Validated forecast/anomaly claims** | Run `flutter test test/intelligence/burn_rate_forecaster_test.dart test/intelligence/anomaly_detector_test.dart test/intelligence/anomaly_suppression_test.dart test/intelligence/derived_reads_service_test.dart test/intelligence/assistant/query_engine_test.dart`. Validator rejects malformed/unknown versions and stale evidence; fixed renderer shows estimate/range/as-of/coverage; insufficient cases produce no number. Synthetic anomaly precision and false-alarm gates pass; nightly and foreground paths agree. | b1–b2 and T-178a; `claim.dart`, `burn_rate_forecaster.dart`, `anomaly_detector.dart`, `derived_reads_service.dart`, `nightly_job.dart`, renderers and focused tests. | No schema change by default; if required, ADR + additive migration/backup/delete coverage first. Disable claim generation to roll back; **~L, split if model evaluation and claim wiring cannot be reviewed separately**. |

## T-178c — Typed English/Hinglish intents over validated results

**Goal / scope:** answer bounded financial questions by selecting and formatting
validated query results and claim IDs. **Non-goals:** open-ended financial
advice, arbitrary narrative generation, generated SQL, unsupported identity
resolution, or balance promises.

### Intent and answer boundary

The local deterministic classifier remains first choice. A model, if enabled,
may map one utterance to a closed typed intent plus validated slots only. The
query engine executes supported deterministic reads. The response layer may
select one or more validated claim/result IDs and fixed-format them; it may not
invent values, claims, explanations, SQL, or payee/category identities. Every
displayed number links to the exact typed result/claim and scope. Unknown,
ambiguous, unsupported, malformed, or unavailable requests ask one concise
clarifying question or abstain. Do not cache an intent if its dates or scoped
identities would be stale on reuse.

Proposed taxonomy (use existing intent/result contracts when semantics match):

| Intent | Slots/results | Boundary |
|---|---|---|
| Spend total | metric, calendar range, optional category/payee, currency bucket | Settled eligible debit rows only; no combined currencies. |
| Compare periods | two explicit comparable ranges, metric, optional scope | Equal elapsed days for partial periods; disclose both windows. |
| Top payees | range, count cap, currency | Rank within each currency; clarify ambiguous payee matches. |
| Forecast | period, currency | T-178b validated forecast claim only; otherwise say insufficient history. |
| “Kitna bacha?” | unresolved semantic slot | Clarify meaning. Do not answer as account balance or cash available; task T-178 excludes balance/runway promises. A budget remaining answer needs a defined budget source and T-098 contract. |
| Recurring | date range, optional payee | Existing recurring series/read path; qualify as detected/expected, not settled future payment. |
| Refunds | range, linked source/effective amount scope | Only source-linked refund facts under the verified refund accounting contract; otherwise clarify/refuse. |
| Card bill later | card/account and billing cycle | Unsupported until T-190 establishes card accounting and validated results; no inference from payment debits. |

Evaluation language mixes must include English, Hinglish, romanized Hindi,
Devanagari Hindi, and code-switching, with informal spellings, common slang,
typos, negation, date ambiguity, payee/category ambiguity, prompt injection,
out-of-scope financial advice, and adversarial merchant text. Store synthetic
utterances and gold slots only. Use fake names such as `XBANK`, `XX1234`, and
round amounts; never copy a user's real phrasing or transaction data.

### Evaluation set and gates

Create at least 200 synthetic utterances with gold intent, slots, expected
clarification/refusal, and the expected typed result ID or result fixture.
Minimum distribution: 60 English, 60 romanized Hindi/Hinglish, 30 Devanagari,
30 code-switched mixed-script, and 20 ambiguous/adversarial/unsupported cases
(overlap allowed only if counts are still met). Balance supported intents and
include at least 20 examples per supported intent; mark currently gated
`card_bill` and unresolved `kitna_bacha` as expected clarification/abstention.

| Metric | Pass threshold |
|---|---|
| Exact intent accuracy | ≥95% overall and ≥90% in each language-mix bucket. |
| Slot exact match | ≥92% over fields applicable to the gold intent; report date, currency, and identity slots separately. |
| Wrong answer rate | ≤1% of answered examples (maximum 2/200); abstention is allowed only where the expected result is ambiguous, unsupported, insufficient, or unavailable. Also report answer coverage to prevent passing by abstaining on everything. |
| Numeric grounding | 100% of rendered numeric tokens resolve to a validated query result/claim field with matching currency, range, and scope; zero model-authored numbers. |
| Unsupported/adversarial leakage | 0 unsupported advice, model SQL, injected instructions, or free-form factual narrative rendered. |
| Clarification quality | ≥95% of gold-ambiguous examples clarify/refuse, with no fabricated default slot. |

Keep a paired evaluation over deterministic-only and model-assisted
classification. Model assistance must not lower safety gates; no-model behavior
must remain usable for supported English and Hinglish forms.

### T-178c slices

| Slice | Goal and acceptance evidence | Dependencies / files likely touched | Privacy, rollback, size |
|---|---|---|---|
| **c1 — Taxonomy and synthetic corpus** | Freeze intent/slot/result schemas and 200+ utterance gold set. Run `flutter test test/intelligence/assistant/hinglish_corpus_test.dart`; corpus validator checks counts, locale/script mix, schema validity, fake-only names, and deterministic expected outcomes. | T-178a claim contract; T-178b forecast semantics for forecast intent; T-190 for card bill; `assistant_intent.dart`, `prompt_catalogue.dart`, new synthetic fixture file/test. | Synthetic only. Revert the new corpus/contracts; **~M**. |
| **c2 — Typed parsing and refusal** | Extend deterministic Hinglish patterns and, if enabled, constrained model extraction. `IntentValidator` rejects extras, invalid ranges, ungrounded identities, ambiguous slots, and unsupported intents. Run `flutter test test/intelligence/assistant/hinglish_eval_test.dart test/intelligence/assistant/assistant_intent_classifier_test.dart test/intelligence/assistant/assistant_controller_test.dart`. | c1; `assistant_intent_classifier.dart`, `assistant_intent.dart`, `assistant_controller.dart`, `llm_runtime.dart` and tests. | Utterance processing stays on-device. Disable model fallback or new intent handlers; **~M**. |
| **c3 — Validated result selection and fixed rendering** | Run `flutter test test/intelligence/assistant/answer_renderer_test.dart test/intelligence/assistant/query_engine_test.dart test/intelligence/assistant/assistant_controller_test.dart test/intelligence/assistant/hinglish_eval_test.dart`. Permit selection/formatting only from result/claim IDs; every shown number passes provenance assertions. Missing/stale result, ambiguity, or unsupported card/refund/balance semantics clarify/abstain. Numeric grounding test is 100%. | c1–c2; `query_engine.dart`, `answer_renderer.dart`, claim renderer and controller tests; dependencies on T-190/T-100/T-098 as applicable. | No raw utterance or result export. Revert selection path; **~M**. |

## T-178d — Local evaluation, performance, staged release

**Goal / scope:** provide offline quality and performance evidence and a
reversible local opt-in rollout for validated results. **Non-goals:** remote
cohorts, cloud inference/telemetry, or using synthetic success as physical
acceptance.

### Local harness and performance gates

The evaluation harness runs offline on the phone against synthetic fixtures and
an explicitly selected owner-local snapshot. Owner data stays on the device;
only aggregate metrics leave via an explicit export action. Do not log utterance
text, transaction IDs, payees, raw amounts, or serialized claims. Persist the
evaluator version and metric definitions, not evaluation rows.

T-178 requires the T-115 device baseline and T-177f measurement plumbing.
T-194 records the supported ARM64 packaging trial and says physical storage and
cold-start checks remain open; it contains no assistant latency or memory
baseline. **Unverified:** I found no T-115 task brief or numeric T-115 baseline
in this worktree. Before setting absolute model memory limits, recover the
supported-phone/device-tier measurements from the owner and cite them in the
implementation report. Do not treat APK size or synthetic harness timing as
device acceptance.

Proposed gates to measure on the supported ARM64 phone (identified in existing
physical QA records as Motorola Edge 50 Pro; verify exact OS/build and device
identity in the T-115 brief before execution):

- Deterministic query and fixed-render path: p95 ≤500 ms on the frozen synthetic
  corpus, warm and cold reported separately.
- Optional intent-model path: p95 ≤10 s and no timeout/ANR; must stay within
  the available-memory admission budget established by T-115/ADR 0009. Report
  peak process memory and post-close memory. Fail release on low-memory kill,
  crash, or memory that fails to return within 15% of pre-load baseline after
  runtime close (proposed threshold; confirm against T-115 instrumentation).
- Forecast evaluation: on-device p95 ≤2 s for the maximum supported history
  fixture; no background run may exceed the existing nightly stage budget.
- Repeat each path at least 30 times across cold and warm runs, with power,
  thermal state, runtime/model version, database size, and sample counts
  recorded. Report p50/p95 and peak memory; no private values in logs.

Absolute targets are proposed planning gates, not known current performance.
If the T-115 baseline contradicts them, adjust before implementation and record
the reason rather than silently waiving the gate.

### Staging, opt-in, and rollback

- Keep new forecast claims and model-assisted Hinglish parsing disabled by
  default. Use a local owner opt-in and persistent kill switch. Stage in order:
  synthetic-only; owner-local shadow evaluation with no user-visible output;
  owner opt-in display; broader default only after quality, privacy, and device
  gates pass.
- `FeatureFlagRepository` already supports persisted typed overrides and reset;
  `feature_flag_repository.dart` defines existing keys and the developer flag
  editor. No current staged user cohort, remote rollout, or owner-facing opt-in
  has been verified. Add the minimum local flag/UI needed; do not introduce a
  cloud control plane. Kill switch must immediately suppress output and stop
  optional inference while leaving capture and ordinary queries available.
- Roll back by clearing/disabling the local flags, hiding new claim kinds, and
  returning to deterministic supported intents. Do not delete source
  transactions. If persisted claim rows or schema fields are introduced, the
  migration must be additive and rollback must ignore the new version safely.
- Keep evidence labels explicit: synthetic test pass, owner-local aggregate
  evaluation, and physical-device acceptance are separate evidence classes.
  No synthetic result proves real-data quality or physical performance.

### T-178d slices

| Slice | Goal and acceptance evidence | Dependencies / files likely touched | Privacy, rollback, size |
|---|---|---|---|
| **d1 — Offline evaluation harness** | Run `dart run tool/grounded_ai_eval.dart --synthetic` offline; owner-local mode must require explicit selection and emit aggregate-only output. `flutter test test/intelligence/grounded_ai_eval_test.dart` verifies no row-level data in logs/export. | T-178b/c; T-177f plumbing; likely `tool/` harness, test fixtures, local report schema. | No network path or raw-data logs. Remove harness; **~M**. |
| **d2 — Device profile and budgets** | On the supported ARM64 phone, record OS/build, p50/p95 latency, peak/post-close memory, model availability, cold/warm behavior, and nightly duration against T-115 baseline. Attach timestamped device-run output plus metric definitions and sample counts; pass proposed gates or revise thresholds with evidence before release. | T-115 baseline recovery, T-194 device identity/packaging context, ADR 0009; evaluator and runtime instrumentation. | Physical device evidence required; synthetic timings are labeled separately. Revert optional model/forecast feature; **~M**. |
| **d3 — Opt-in stages and kill switch** | Run `flutter test test/data/repositories/feature_flag_repository_test.dart test/intelligence/assistant/assistant_controller_test.dart test/intelligence/grounded_ai_rollout_test.dart`. Tests prove default-off, local opt-in, persistent off switch, no inference after disable, safe process restart, and deterministic fallback. Release report lists stage population and unresolved gates without private row data. | d1–d2, T-178a–c; `feature_flag_repository.dart`, relevant settings/controller wiring and tests. | Local-only opt-in; no remote cohort service. Disable flags/hide new claims for rollback; **~M**. |

## Shared fixture and evidence rules

- **Ledger generator:** seeded synthetic accounts with fake IDs/payees, round
  amounts, source currency, local calendar time, categories and eligibility
  flags. Generate settled debit, credit/refund-linked and unlinked, owned
  transfer, duplicate, analytics-excluded, non-spending-category, missing-day,
  recurring, changed-habit, and injected-anomaly cases. Include a coverage mask
  independent of transaction presence so a genuinely quiet day differs from
  unknown capture. Freeze seed and generator version in every report.
- **Utterance corpus:** UTF-8 JSONL or equivalent with `case_id`, `text`,
  `language_mix`, `script_mix`, `typo/slang/adversarial` tags, gold intent,
  exact gold slots, expected result fixture/claim ID, and expected
  answer/clarification/refusal. Synthetic names only (`XBANK`, `XX1234`). Never
  include production prompts or copy owner language into fixtures.
- **Owner-local evaluation report:** aggregate sample sizes, metrics, confidence
  intervals, suppression/refusal counts, method/runtime versions, and device
  profile only. Do not export raw examples, transaction-level outputs, IDs,
  dates, payees, or amounts. Small segment metrics remain on-device.

## Risks and owner decisions

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---:|---:|---|
| R1 | Transaction capture gaps make a recorded-spend range look like a complete household-spend prediction. | High | High | Label recorded-data scope; require coverage contract and abstain on unknown gaps. |
| R2 | Quantile calibration is unstable for short or irregular histories. | High | High | Require origin floors, bucket calibration, confidence intervals, and suppression cap; block release if gates fail. |
| R3 | Refund/transfer/currency semantics diverge between claims and assistant queries. | Medium | High | Reuse `FinancialEligibility`, source-currency buckets, verified refund links, and parity tests. |
| R4 | Ambiguous “kitna bacha?” or card-bill requests are answered as balances from incomplete data. | Medium | High | Clarify; keep balances unsupported; gate card bill on T-190 and budget remaining on T-098 contract. |
| R5 | Hinglish and typo corpus is too narrow, making accuracy look better than real use. | Medium | High | Meet per-language minima, publish bucket metrics, add owner-approved synthetic adversarial cases, and preserve abstention. |
| R6 | On-device model load exceeds memory/latency budget on supported ARM64 hardware. | Medium | High | Recover T-115 baseline; measure cold/warm p95 and peak/post-close memory; default-off with kill switch. |
| R7 | Owner-local evaluation leaks row-level data in logs or exported diagnostics. | Low | High | Aggregate-only serializer, privacy tests, explicit export, no remote telemetry. |
| R8 | A future claim may outgrow the current versioned insight payload. | Low | Medium | Keep payload additive; require an ADR and migration coverage only if a measured requirement cannot fit the current envelope. |

Open owner decisions:

1. Should “kitna bacha?” mean remaining user-defined budget, projected recorded
   spend versus a budget, or something else? Account balance/cash available is
   out of scope without verified balance data.
2. Should owner-local aggregate metrics be exportable at all, and which aggregate
   fields are acceptable? Default proposal: no export until explicit action.
3. Are the proposed numeric quality and latency thresholds acceptable, or should
   the first implementation use stricter/looser gates after the T-115 baseline
   is recovered?

## Dependencies and implementation order

1. T-178a evidence/eligibility contract is complete; finish the open T-177a
   production/coverage audit before broadening automatic decisions.
2. T-178b b1–b3, with rolling-origin quality gate before enabling forecasts.
3. T-190 card accounting before `card_bill`; verified refund accounting before
   refund result intents; T-098 contract before any budget-remaining semantics.
4. T-178c c1–c3, retaining deterministic no-model support and passing corpus
   gates before optional model assistance.
5. T-178d d1–d3 only after T-115 baseline and T-177f measurement plumbing are
   available. Keep physical/device and owner-local gates open until evidence is
   recorded.

Do not promote T-178b/c/d as completed based on synthetic milestones alone.
