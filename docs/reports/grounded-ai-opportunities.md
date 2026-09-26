# Grounded AI opportunities

Status: research and product proposal, 2026-09-26. No code or data changes.
Related: [transaction assistance plan](../plans/smart-transaction-assistance.md),
[ADR 0011](../decisions/0011-evidence-backed-assistance.md).

## Executive summary

The most useful AI for PaisaTrack is practical help with the user's own
recorded transactions: fill only fields supported by evidence, explain patterns
with links to the transactions behind them, answer questions using exact local
queries, and estimate future spending with a visible uncertainty range.

Hinglish: *AI wahi bataye jo app ke asli records se nikalta hai. Jo data app ke
paas nahi hai, us par guess karke fact na banaye. Number database se aaye; model
sirf us number ko samajhne aur seedhe shabdon mein batane mein madad kare.*

The near-term opportunity is better grounded assistance and analytics, not a
bigger model. Reuse the existing deterministic insights and local query engine;
first fix their evidence, coverage and comparison limits. Use statistical
methods for totals, patterns and forecasts. Give the local language model the
small job of interpreting questions or selecting supported claim IDs for
fixed plain-language rendering. It should not make
up missing purchases, merchant identities, user intent or amounts.

## What exists today

These are observations from the current source tree, not promises of production
quality:

- **Rules and categorization:** `lib/enrichment/categorizer.dart` runs user
  rules, optional merchant memory, an optional classifier, the seed map, a
  person/self transfer default, optional LLM suggestion and fallback. The
  production `categorizerProvider` wires rules, seed map, classifier and
  threshold only; it does not supply merchant memory or the LLM suggester. So
  those hooks are not active in the standard capture provider.
- **Local category model:** `lib/enrichment/local_classifier.dart` contains a
  small softmax classifier and trainer over explicit category feedback. The
  training path requires a minimum feedback count. `predict()` currently calls
  `_features` without merchant-count, recency or amount-z-score inputs, so those
  optional feature slots are zero in normal prediction. A probability-like
  softmax score is not automatically a calibrated probability of correctness.
- **Exact answers:** `lib/intelligence/assistant/query_engine.dart` computes
  totals, breakdowns, comparisons, recurring items and active insight lists
  from local records. `AnswerRenderer` formats the result. This is the right
  owner for arithmetic; the assistant intent classifier should only route a
  question into supported query shapes. Its transaction query currently checks
  date range, deleted/duplicate/excluded state and owned transfers, but omits
  `lifecycleState == settled` and spending-category eligibility. Dashboard
  aggregates reuse `FinancialEligibility`; assistant answers can therefore
  disagree with dashboard totals when pending/reversed rows or non-spending
  categories are present. Treat shared eligibility and parity coverage as a
  T-178a prerequisite; T-178c financial questions depend on its completion.
- **Existing insights:** deterministic code detects recurring series,
  anomalies, fees, price changes, missed recurring payments, category changes
  and a month-end burn-rate projection. These are statistical/rule-based
  features, not generative AI. They already provide useful evidence to explain.
- **On-device LLM:** `NarrativeInsightGenerator` sends aggregate insight JSON
  to the local runtime and asks for one short qualitative monthly observation.
  It rejects digits and advice words. This prevents model-authored numbers but
  does not prove that a qualitative statement is supported by a specific
  aggregate or that it describes the user's situation correctly.
- **Hardware and availability:** `PlatformLlmRuntime` has feature, model,
  device, timeout and failure states. Native code reports model/runtime and
  device eligibility. The optional local model can be absent, unsupported,
  slow or resource-limited; capture, exact queries and deterministic analytics
  must remain useful in those states.

## Ranked opportunities

| Rank | Opportunity | What the user gets | Best method | Priority |
|---|---|---|---|---|
| 1 | Transaction auto-fill and learned corrections | Known payees/categories are filled from explicit rules and confirmed history; only uncertain fields need a quick answer | Deterministic parsing and rules, then tested local classifier; LLM may explain a suggestion but not establish facts | T-177 |
| 2 | Ask questions about recorded money | “How much did I spend on food last month?” returns a date range, total, matching count and tap-through records | Local intent routing plus deterministic database query and renderer | Improve existing assistant |
| 3 | Spending-pattern explanations | “What changed this month?” points to a verified comparison, dates and transactions | Statistical comparisons and typed evidence; optional selection/ranking of validated claim IDs with fixed rendering | T-178a |
| 4 | Recorded-spending month-end estimate | A range, assumptions and known upcoming recurring payments; uncertainty rises when capture is incomplete | Statistical forecast and interval calibration; no LLM arithmetic | T-178b |
| 5 | Unusual-spend alerts | Notice an unusual merchant/category amount and show its own baseline and transactions | Robust statistical detector, minimum-history and materiality gates | Improve existing anomaly path |
| 6 | Recurring payment and price changes | Expected payment date/amount and observed changes; user can correct a mistaken series | Periodicity detection and exact transaction evidence | Improve recurring insights |
| 7 | Optional supplied-document matching | A user-selected receipt/screenshot can help match an existing payment and extract visible evidence | On-device OCR/parser and explicit user confirmation | Later discovery; separate consent and feasibility review |

Ranks prioritize reduced effort, useful analysis, and feasibility with data the
app already records. Items 2–6 should not be blocked on a language model. Item 7
uses new evidence supplied by the user, not model-generated financial data.
A cash-balance/runway estimate is deferred until fresh verified balances and
obligations exist; captured income minus expenses is not an account balance.

### 1. Finish transaction help before adding more AI

The [T-177 plan](../plans/smart-transaction-assistance.md) covers payee
recognition, confirmed-history learning, one-question review, correction scope,
undo and grouped exceptions. The important AI work is making signals
trustworthy: production wiring, measured classifier quality, ambiguity
abstention, and preserving field provenance. A model cannot infer whether a
transfer to a person was dinner, a gift or a loan repayment when the records do
not say.

### 2. Make existing insights explainable and comparable

Every displayed claim should be represented internally as a typed result with
the period, calculation, source transaction IDs, sample count, and any
limitations. Tapping the claim should open the rows that support it. Arithmetic
and eligibility rules remain deterministic. An LLM may select only validated claim IDs; fixed templates render their
meaning and numbers. Arbitrary generated prose must not reach the answer,
even if it contains no digits.

Before presenting category changes, compare equivalent elapsed portions of the
month or use a complete-month-only comparison. Current code compares the
current partial month with the full previous month, which can make a change look
larger or smaller simply because fewer days have elapsed.

The burn-rate forecast fills calendar days without captured transactions with
zero. A genuinely quiet day and a day with missing SMS/import coverage look the
same to that calculation. Until the app can estimate or display capture
coverage, label this forecast as conditional on recorded data and avoid strong
claims when coverage is unknown. Do not silently treat missing records as
observed zero spending.

### 3. Forecast with honest uncertainty

Start with simple baselines: trailing mean/median, same-period history, or a
seasonal-naive estimate when enough history exists. Compare any more complex
model against these. Return a central estimate and an interval, plus the date
and data coverage used. Fewer history periods, irregular income/spending,
missing capture and outliers should widen the interval or cause abstention.

Evaluate a forecast by making predictions at earlier dates and comparing them
with what happened later. This is rolling-origin evaluation: training and
features at each test point may use only information available at that point.
Randomly splitting transaction rows leaks future patterns into the past and is
not appropriate for time-series assessment. Measure error and interval
coverage, including whether nominal ranges contain actual outcomes at roughly
the advertised rate. See [time-series cross-validation](https://otexts.com/fpp3/tscv.html),
[prediction intervals](https://otexts.com/fpp3/prediction-intervals.html), and
[simple forecast baselines](https://otexts.com/fpp3/simple-methods.html).

## Grounding contract for every AI feature

1. **Use only recorded evidence.** A source message/import/user correction can
   support a transaction fact. A derived insight can support a summary. No
   synthetic transaction, invented receipt line, assumed purpose or guessed
   balance becomes a fact.
2. **Keep source facts and estimates distinct.** Amount, date, direction,
   account and references need a source link or explicit user correction.
   Categories and payee names carry method and confirmation state. Predictions
   are estimates, never settled transactions.
3. **Show the evidence and scope.** Include period, filters, number of records,
   and an easy route to supporting rows. State when a result covers recorded
   data only or omits pending/excluded transfers.
4. **Abstain when evidence is weak.** Use “not enough history” or “I can’t tell
   from these records” when the sample is small, fields are ambiguous or
   coverage is unknown. A blank result is safer than fabricated certainty.
5. **Separate models by job.** SQL/repository queries own arithmetic and
   filtering. Statistical code owns anomaly scores and estimates. The LLM may
   map language to a supported query or select from a closed set of typed claims
   for fixed rendering.
   It must not write or execute SQL, or create unsupported facts.
6. **Keep human correction available.** Let the user inspect, correct, dismiss
   or undo a derived result. Explicit user feedback can teach future matching;
   an automatic label or ignored prompt is not confirmation.

### Example display templates (hypothetical, not findings about any user)

- “For **[date range]**, recorded food spending was **[total]** across **[count]**
  payments. Compared with the same days in **[comparison range]**, it was
  **[difference]**. **[View payments]**”
- “Based on **[N] complete months** and recorded transactions through **[date]**,
  this month may end near **[estimate]**; a reasonable historical range is
  **[low–high]**. Missing or unrecorded payments are not included.”
- “**[Payee]** is usually tagged **[category]** in **[confirmed count]** of
  **[eligible count]** corrected payments. This one is only a suggestion.
  **[Confirm] [Change] [Yaad nahi]**”
- “Recorded **[category]** spending is above its usual range for **[period]**.
  The comparison uses **[baseline periods]**; **[count]** payments support it.
  **[See payments] [Dismiss]**”

Replace every bracket with a query result; never show bracket text as a real
insight. Hide the comparison if its period, denominator or source rows are not
available.

## Measurement and release gates

For each feature, save a versioned, minimal decision record: input window,
method/model version, output, uncertainty, and eventual explicit correction or
observed outcome. Avoid retaining raw prompts or message bodies for analytics.
Use only data already permitted under the app's local-data and privacy policy.

- **Auto-fill:** report precision and coverage, separately for new/repeated and
  mixed-use payees; include a confidence interval and sample size. Compare
  correction effort per 100 eligible transactions. Low evidence remains
  suggestion-only.
- **Insights:** audit claim-to-row traceability and calculation reproducibility;
  measure useful/dismissed claims and correction rate by insight type. Do not
  optimize solely for how many cards the model writes.
- **Forecasts:** compare with simple baselines on chronological rolling origins;
  report absolute/percentage error where meaningful, interval coverage and
  interval width by horizon and data sufficiency group. Baselines must be
  evaluated on the same dates.
- **Latency and device cost:** measure p50/p95 response time, peak memory,
  battery impact and model download/storage size on representative supported
  devices. LLM output must not block transaction capture or exact answers.
- **Privacy:** process financial records on-device, as required by ADR 0002.
  No cloud inference or telemetry containing financial content is part of this
  proposal. Keep optional local model controls and a usable no-model fallback.

Use chronological holdout data. At each evaluation date, train only on earlier
confirmed labels and use only features that existed then; never let a future
correction or transaction influence an earlier prediction. Synthetic fixtures
remain useful for edge cases, but are not evidence of real-world accuracy.

## Proposed delivery map

These are proposed scopes from the current [T-178 task brief](../tasks/T-178.md),
not completed work. Keep feature work aligned with T-177 and ADR 0011.

| Ticket | Proposed scope | Exit evidence |
|---|---|---|
| T-178a | Evidence-linked insight claims and fair comparisons | Each claim reproduces from linked rows; equal-period comparisons, exclusions, missing evidence and unsupported qualitative claims are tested |
| T-178b | Forecast ranges, data sufficiency and evaluation | Rolling-origin baseline comparison, amount error, interval coverage/width, low-history abstention and capture-gap handling |
| T-178c | Typed English/Hinglish assistant over verified results | Supported question evaluation, exact totals/filters, ambiguity clarification, evidence links and honest unavailable states |
| T-178d | Local quality and performance release gate | Chronological quality report, sample/cohort limits, target-device latency/memory, offline and rollback evidence |

Before expanding assistant financial questions, reuse `FinancialEligibility`
where the query metric permits it and keep metric-specific rules explicit.
Add parity tests that seed settled and pending rows, excluded and owned
transfers, duplicates, deleted rows, spending and non-spending categories, plus
credits/refunds; compare assistant results with the corresponding Dashboard
query for the same period and scope. This tests shared policy rather than
copying a second hand-maintained predicate. Preserve intentional metric
differences (such as income versus spending) in the test expectations.

Prerequisites: finish T-177a integration/evidence audit, settle the transaction
correction and undo review in the feature plan, and test baseline data quality
before broadening automatic decisions. Do not add a larger or cloud model as a
substitute for this work.

## Recommendation

Prioritize in this order: trustworthy transaction corrections (T-177), typed
evidence-backed insights and fair comparisons (T-178a), measured forecast
uncertainty (T-178b), then typed English/Hinglish questions over verified
results (T-178c), with local quality and performance as the release gate
(T-178d). This uses real local records, helps the user act on them, and keeps
the model in the role it can safely do well: language, not financial truth.
