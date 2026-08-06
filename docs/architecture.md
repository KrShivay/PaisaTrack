# Architecture

PaisaTrack is a local-first Flutter/Android application. Android owns privileged
SMS and Keystore integration; Dart owns parsing, domain logic, encrypted data
access, intelligence, and UI state.

## Runtime flow

1. Android filters transactional SMS and sends accepted messages to Dart.
2. The parser cascade produces a normalized transaction or a typed rejection.
3. Merchant resolution, categorization, deduplication, and decision policy enrich
   the record.
4. Repositories write the source and normalized state atomically to SQLCipher.
5. Riverpod providers expose transactions, review queues, analytics, recurring
   series, insights, settings, and assistant results.

The presentation layer is a four-tab Bloom shell (Home, Activity, Sort, Trends)
with an Ask sheet and secondary task sheets/pages. `docs/product-status.md`
records which Bloom paths are complete and which remain unsafe or partial.

## Capture

- `SmsReceiver` handles live messages.
- `SmsInboxReader` and `SmsHistoryImporter` keyset-page full inbox history,
  checkpoint completed pages, isolate row failures, batch each page in one
  database transaction, and support idempotent re-import.
- `SmsIncrementalCatchUp` runs after the versioned initial import and on
  open/resume. It finishes the first-known boundary page plus one older page to
  recover recent live-ingest gaps without rescanning full history. Live messages
  continue through `SmsReceiver` → `CapturedSmsSink` → EventChannel; messages
  received while the process is absent are recovered from the inbox on open.
- Live and historical messages share `SmsIngestor`.
- The parser order is template → conservative generic parser → optional local
  LLM extractor.
- OTP, promotional, failed, and future-event messages do not become settled
  transactions.
- `DuplicateSuppressor` links cross-source echoes instead of deleting evidence.

Future recurring-calendar work must route bill-due/autopay reminders to expected
events, not relax the transaction parser's future-event rejection.

## Storage and privacy

- Drift is opened through SQLCipher.
- A generated database passphrase is protected by Android Keystore.
- `raw_sms` is retention-limited; normalized transactions persist.
- Original merchant text, VPA, references, source, and confidence evidence are
  preserved separately from user corrections and future labels.
- Payee labels use a rebuildable SQL evidence index: aggregation, search,
  unresolved filtering, and keyset paging happen in the database while the
  original merchant/VPA fields remain authoritative. Duplicate suggestions are
  read-only until the user confirms a merge.
- Backup files are passphrase-encrypted before leaving app memory. The archive
  enforces 32 MiB encrypted-file, 16 MiB decoded-payload, 50,000-row per-table,
  and 200,000-row total ceilings, accepts only the shipped Argon2id profile,
  and excludes expired raw SMS. Settings uses a session-based Android
  document gateway and the authenticated v2 chunked envelope; v1 JSON/AES-GCM
  imports remain compatible. Export pages Drift rows, and import restores
  newline-delimited rows inside one transaction with progress and cancellation.
- Delete-everything closes the database, removes DB/key/settings/import state,
  and recreates only default categories.

## Identity and categorization

`MerchantResolver` checks normalized aliases, then local embedding similarity,
then creates a merchant when no safe match exists. `Categorizer` applies:

1. user rules;
2. the local classifier when its category threshold is met;
3. the seed keyword map;
4. `Other` at review confidence.

`DecisionPolicy` chooses `auto`, `asked`, or `needs_review`. Unseen UPI
counterparties fail closed; seen counterparties rejoin the confidence policy
and can become automatic. Generic VPA extraction rejects email-domain suffixes.
Manual entries are confirmed. Category/description corrections write feedback,
rules, learned aliases, and transaction state in one database transaction.

User labels extend canonical merchant/counterparty identity and alias resolution.
They can map multiple aliases, preview affected history, and refuse conflicting
merges without replacing raw source fields.

## Analytics and intelligence

- `FinancialCalendar` turns local, half-open calendar days/months into UTC
  instants for SQLite queries. Dashboard periods, forecasts, anomalies,
  insights, and the Ask quota use it; tests inject the India offset around the
  local midnight/month boundary.
- `FinancialEligibility` is the shared spending contract: settled debit only,
  excluding deleted, duplicate, opted-out, and owned-transfer rows, and
  requiring a spending category (uncategorised defaults to spending).
- Dashboard providers read SQL totals and grouped category, merchant, and trend
  aggregates. Transaction feeds load 100 newest rows at a time; recent cards use
  a separate six-row period query.
- Payment sources can be named, marked owned/active, and excluded from analytics.
  Conservatively paired transfers between owned sources are also excluded from
  aggregates without hiding either transaction.
- Recurring detection derives series from settled history.
- Anomaly, forecast, and insight engines are deterministic and consume the
  same eligibility contract as Dashboard.
- Nightly work purges expired raw SMS, refreshes recurring/baseline/classifier
  state, and recomputes insights with checkpoints.

Current boundaries that must be preserved while fixing the UI:

- SQL aggregates are the only valid source for full-period totals. A loading or
  failed aggregate must not fall back to the bounded 100-row Activity feed.
- Current-month budget guidance is not valid for a historical/custom period.
- Empty financial state is shown only after a successful empty query; loading
  and failure remain distinct states.
- The global monthly-budget/merchant-cap implementation is a prototype stored
  in `baselines`, not the planned category-budget domain.

Known scale limits are the 100-row Activity and Review windows, client-side
payee aggregation, quadratic owned-transfer reconciliation, and the bounded
legacy in-memory backup compatibility helpers. The production document path
now streams authenticated rows; physical SAF/provider acceptance remains
release evidence.

Refund links, source inclusion rules, and statement reconciliation must feed a
single explained spending-total contract before budgets consume those totals.

## On-device models

- The text embedder supports merchant resolution.
- The optional Qwen3 0.6B mixed-INT4 model runs through LiteRT-LM and is shared
  by unmatched-SMS extraction, qualitative aggregate narratives, and assistant
  intent fallback (ADR 0009).
- Model files are explicitly downloaded, integrity-checked, app-private, and
  deletable.
- Missing/unsupported models return typed unavailable results; deterministic
  paths continue.
- Each inference uses isolated session state. Native model memory closes after
  idle timeout, backgrounding, engine cleanup, replacement, or deletion.

## Grounded assistant

`AssistantIntentClassifier` resolves common questions without loading the model.
Ambiguous supported questions use a compact strict-schema model fallback.
`IntentValidator` produces a typed intent, `AssistantQueryEngine` reads local
repositories, and `AnswerRenderer` interpolates only deterministic query fields.
Model prose and model-authored numbers cannot reach the answer.

## Future extension boundaries

- T-102: import statements through preview, fingerprinting, and reconciliation;
  do not bypass `SmsIngestor` invariants when creating normalized rows.
- T-100: represent transaction relationships; do not mutate/delete originals.
- T-101: store expected events separately from transactions.
- T-098: compute budgets from the shared net-spending contract.

See `docs/schema.md`, `docs/privacy.md`, and ADRs before changing these boundaries.
