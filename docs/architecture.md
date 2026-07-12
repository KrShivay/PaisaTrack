# Architecture

PaisaTrack is organized as a local-first pipeline:

1. Native Android SMS capture filters and forwards candidate messages.
2. Dart capture code parses SMS into the normalized transaction record.
3. Intelligence enrichers resolve merchants, categories, recurring status, and insights.
4. Riverpod owns the app database lifetime through `appDatabaseProvider`, which
   opens encrypted SQLite with the Android Keystore-backed passphrase provider
   and can be overridden with an in-memory database in tests.
5. Repositories persist records in encrypted SQLite.
6. Experience screens read only normalized/enriched records.

All UI follows the binding conventions in [design-system.md](design-system.md);
themes and tokens live in `lib/core/theme/` (dark-first, light as an equal
derived variant). Settings owns theme selection, ask budget, feature-flag
readouts, and local data reset.

Runtime SMS access is gated by `SmsPermissionGate` (platform channel
`com.paisatrack/sms_permissions`), surfaced through `smsPermissionControllerProvider`
and the onboarding screen. Denial is non-fatal: the app stays usable and
explains the degraded (no automatic capture) state rather than blocking.

Live SMS delivery uses a separate EventChannel (`com.paisatrack/sms_events`).
Android forwards filter-approved `CapturedSms` payloads into that channel, and
Riverpod boots the Dart listener through `smsCaptureBootstrapProvider` only
after permission is granted and the encrypted database is ready.

## Capture pipeline (Phase 1, shipped)

1. `SmsFilter` (Kotlin) allowlists bank/UPI DLT senders and rejects OTP,
   promo, and personal messages before anything crosses to Dart.
2. Historical backfill (`SmsBackfiller`, one-time on first grant, window set by
   `AppConstants.smsBackfillMonths`) and live capture share the same
   `SmsIngestor` write path.
3. `ParserCascade` runs `TemplateMatcher` over the real bank registries in
   `assets/templates/{axisbk,indusind,paytmb,sbi}.json` (loaded via
   `parserCascadeProvider`), then a conservative on-device generic fallback.
   The fallback requires direction + INR amount + account/channel/VPA context,
   rejects OTP/future/failed messages, and emits `src: 'generic'` at <=0.6
   confidence; therefore it can never silently auto-label. Parse success writes
   a transaction; failure leaves the raw SMS `processed=false`, visible on the
   dev Unparsed screen, which surfaces the template-miss and generic-guard
   rejection stages for on-device template-gap triage. No cloud parsing path
   exists (ADR 0002).
4. `DuplicateSuppressor` marks cross-source echoes (paired bank+wallet SMS)
   within a 10-minute window; suppressed rows stay stored for audit.
5. Raw SMS rows are purged after the retention window; transactions persist.

## Enrichment (Phase 2, shipped)

`Categorizer` (`lib/enrichment/`) runs the PLAN §7.4 ladder at ingest time,
steps 1 + 3 for now: user-taught rules (`RuleRepository`, match types
`merchant` substring / `counterparty` exact-VPA, confidence 1.0, hit counts
maintained) → bundled seed keyword map (`assets/seed/category_seed.json`,
longest-key-first substring match, 0.8) → `other` at 0.3. Both live capture
and backfill construct `SmsIngestor` with the categorizer
(`categorizerProvider`), and the outcome is recorded in the transaction's
`confidence_json` under `category` (`c`, `src`, optional `rule_id`). The same
atomic transaction records provisional merchant evidence (`v`, `c`, `src`)
from the parser until the Phase 3 merchant resolver replaces that block.
`TransactionConfidenceTrail` reads parser/merchant/category blocks without
breaking legacy parser-only rows and exposes them through transaction detail.
The
classifier (step 2) and on-device LLM (step 4) slot in during later phases.

`DecisionPolicy` implements static PLAN §7.5 thresholds from `AppConstants`.
`SmsIngestor` computes transaction status before insertion from parser
confidence, category confidence, same merchant/VPA history, unseen P2P
counterparty state, and the count of transactions already marked `asked` today.
Rows land as `auto`, `asked`, or `needs_review`; manual entries stay
`confirmed` because the user typed them.

## Correction surfaces (Phase 2, shipped)

Two surfaces turn `asked` / `needs_review` rows into confirmed, category-labelled
transactions, and both funnel through one write path.

`TransactionRepository.correctWithRule` is the single correction boundary: inside
one `_database.transaction` it inserts a teaching rule (via `RuleRepository`),
stages `feedback` rows for the changed `category_id` (and `description` when a
free-text note is supplied), and updates the transaction to `status='confirmed'`
— all commit or roll back together (PLAN §1 principle 3). A `context` string tags
where the correction came from (`ask_now`, `batch_review`). `confirm()` is the
lighter sibling: it sets `status='confirmed'` without changing the category, for
"this guess was right" swipes.

**Ask-now notifications (T-044)** interrupt at most `askDailyBudget` times/day
(the Settings slider, falling back to `AppConstants.askNowDailyBudget`; threaded
into `SmsIngestor` so the policy and the notifier agree on the budget).
`AskNowPayloadBuilder` builds a notification with the top three category guesses
as action buttons (best guess first) plus a free-text remote input.
`askNowNotificationControllerProvider` (watched in `app.dart`) shows the
`asked`-status queue and drains answers on every build — i.e. on app start. The
Android `AskNowNotificationReceiver` persists button/free-text answers to
SharedPreferences, so responses given while the app is killed survive; the Dart
side reads them via the `com.paisatrack/ask_now` method channel, which returns
then atomically clears the store (answers apply exactly once). Free-text resolves
to a matching category by name, else lands `Other` with the text kept as the
description. Credits only offer income-side categories: the builder drops any
spending category except `Other` when the transaction is a credit, so income
never suggests Food/Groceries — credit actions surface `Other`/`Transfers`/
`Income`. Android 13+ requires the `POST_NOTIFICATIONS` runtime permission.

**Weekly review (T-045)** is a `HomeShell` tab over the `needs_review` queue
(`watchReviewQueue()`: not deleted, not a duplicate, newest first). Swipe
confirms (`confirm()`); tap opens a correction sheet that calls
`correctWithRule(context: 'batch_review')`. An "All caught up" empty state shows
when the queue is clear.

**Parse confirmation (T-073)** appears only for low-trust parses: generic
fallback rows or templates marked `public` provenance under ADR 0005. The
transaction detail and weekly-review correction sheet offer **Confirm** or
**Fix** for amount, direction, and merchant. Confirm writes one
`feedback(parse_verdict='ok', context='parse_confirm')` row. Fix updates the
transaction and records each changed parse field plus a corresponding
`parse_verdict` correction in the same database transaction. High-trust device
templates never show this prompt.

**Template trust ledger (T-074)** rebuilds public-template trust from those
`parse_verdict` rows. It stores compact per-template counters in `model_meta`:
20 `ok` confirmations with no amount/direction correction promote a public
template to 0.97; either correction keeps it at 0.85 and exposes its template
id on the developer diagnostics screen. The feedback rows remain authoritative;
the metadata is a parse-time cache only.

## Verification tooling

`scripts/reconcile_statement.py` reconciles bank-statement XLSX exports against
SMS-parsed transactions (fixtures or an on-device JSON export via the debug-only
dev-screen button). Phase 1 exit was proven with it: 94.4% statement coverage,
zero contradictions (WORKLOG "PHASE P1 EXIT: PASS"). T-047 later added
IndusInd NEFT/ACH-credit templates and reports 99.03% coverage in the
fixture/SMS-dump simulation; final device export evidence is deferred to the
Phase 2 exit pass. Statements and reports live in the gitignored
`BankStatement/` folder.

Raw SMS bodies are temporary capture inputs and must not appear in release logs,
network payloads, or unencrypted exports. Settings `Delete everything` closes
the Riverpod database, deletes SQLCipher database sidecars, clears the Android
Keystore-wrapped passphrase via `com.paisatrack/database_passphrase`, resets
app-private settings, and reopens a database seeded only with bundled
categories.

Export/import uses `com.paisatrack/documents`, a narrow platform channel over
Android `ACTION_CREATE_DOCUMENT` / `ACTION_OPEN_DOCUMENT`. Dart prepares the
encrypted backup or debug JSON bytes; native code streams them only to the URI
the user selected. Picker cancellation returns without a partial file, and no
storage permission is declared.

Weekly review groups `needs_review` rows by resolved merchant id, then VPA or
normalized merchant text. Bulk and per-group confirmation use one atomic status
update and deliberately leave category assignments unchanged; row tap correction
and swipe confirmation remain independent paths.

## Recurring detection (Phase 3)

`RecurringDetector` runs as an idempotent nightly batch over non-deleted,
non-duplicate transactions with a resolved merchant. It sub-clusters amounts
within 5%, then accepts weekly (6–8d), monthly (26–35d), quarterly (80–100d),
or yearly (350–380d) median gaps when gap CoV is below 0.25 and at least three
occurrences exist. The upsert records the median-based next date, rising last
three amounts, and a missed status after a 20% period grace window. Credits are
income; debit labels identify EMI/bill keywords and otherwise subscriptions.
The Recurring tab watches these rows ordered by next expected date, shows the
expected amount and cadence, and calls out rising prices or missed occurrences.
Selecting a series opens the transaction list filtered to its merchant so the
user can inspect the supporting payments.

`AnomalyDetector` maintains population mean/standard deviation baselines with
Welford updates for category-week and merchant-month aggregates. It checkpoints
each period via `updated_at`, compares against the prior baseline only after
eight periods, and writes deterministic anomaly insights above 2.5σ with the
top three contributing transaction ids.

`BurnRateForecaster` compares current UTC month debit spending with the trailing
three calendar months. It adds the per-calendar-day median for every remaining
day to current spend, then compares the projection with the three-month average.
Deleted and duplicate rows and credits are excluded. A deterministic `forecast`
insight exists only when absolute deviation is strictly above 10%; reruns remove
a stale insight. A calendar day absent from a shorter historical month is left
out of that day's median rather than treated as zero spending.

`InsightsEngine` atomically recomputes five no-LLM insight types for each UTC
month: multiple active subscription series for one merchant, fees and penalties
total, rising recurring prices, category month-over-month changes above 10%, and
missed debit autopays. IDs include the reporting month so history is retained;
reruns preserve the user's dismissed flag and remove only stale rows owned by
this engine. Forecast and anomaly rows remain owned by their dedicated engines.

The Insights screen watches non-dismissed rows for the current UTC reporting
month. It renders only the engine's structured JSON fields into fixed report,
savings, forecast, and anomaly copy; transaction ids and raw capture text are
never displayed. Dismissal persists on the insight row, and an empty state
explains that reports appear after local patterns are detected.

## On-device text embedder (Phase 3, T-050)

`Embedder` (`lib/intelligence/models/embedder.dart`) returns a fixed-dimension
float32 vector for a normalized merchant string, backed by the pinned MediaPipe
Universal Sentence Encoder (ADR 0007) through the `com.paisatrack/embedder`
platform channel. `EmbedderBridge` on the Kotlin side owns the model lifecycle:
`downloadModel` fetches the generation-pinned artifact into app-private storage
via a temp file, verifies size and MD5 against the ADR pin, and installs it
atomically — a partial or unverified file is never left behind; `deleteModel`
is the Settings-facing delete control; `embed` maps the verified file as a
read-only buffer into a lazily created MediaPipe `TextEmbedder` and runs on a
dedicated single-thread executor. Inference never touches the network; the
download method is the app's only network use (ADR 0002) and prompted the
INTERNET manifest permission, documented inline in the manifest.

The Dart service never throws: model-missing, native failure, and
missing-plugin (test host) paths all return `null` so ingest and the T-051
merchant resolver degrade to alias/creation behavior without blocking.
`NoopEmbedder` serves widget/unit tests. Determinism is proven on-device by
`integration_test/embedder_determinism_test.dart`, which downloads/verifies
the pin, asserts bit-exact repeat embeddings over fixed inputs, distinct
vectors for distinct inputs, a stable dimension, and prints the dimension for
back-filling ADR 0007 before T-051 stores embeddings in
`merchants.embedding` (float32 little-endian BLOB).
## Phase 4 — shared on-device LLM

`LlmRuntime` is the single feature-flagged inference boundary shared by the
fallback extractor, narrative generation, and assistant. Its MediaPipe Android
implementation loads the ADR 0008 Qwen2.5 `.task` file from app-private storage.
`complete()` and strict-schema `extractJson()` never have network capability;
only the Settings-initiated resumable downloader opens HTTP, and it promotes a
partial file only after the pinned size and SHA-256 both match. Missing models,
disabled flags, and unsupported/low-RAM devices return typed no-op results so
deterministic callers continue unchanged. `llama.cpp` over an ungated Qwen2.5
GGUF remains the recorded fallback if MediaPipe proves unsuitable.

A complete partial is verified and promoted before any further HTTP Range
request, so an interrupted download cannot get stuck requesting past EOF. The
native inference handle is cached only while the Flutter engine is alive and is
closed during engine cleanup or before model replacement/deletion.
