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

The shell reserves horizontal system insets (including display cutouts) around
the floating navigation pill. Its tab Navigators inherit the larger of the
system `padding` and `viewPadding` on each horizontal edge. They also reserve a
shared bottom inset equal to the device's bottom system inset plus the pill's
height and gap, so scrollable content and `SafeArea` actions stay clear of
system bars and the persistent pill.
Scrollables with explicit padding use `BloomBottomInset.contentPadding`;
Scaffold FABs use the shared nav-aware location because their default location
ignores overridden padding. The undo toast uses the same shell geometry. The
full-screen Ask sheet is outside the tab Navigator and handles only its system
safe area.

The shell retains every visited tab Navigator and route stack. System back
first offers `maybePop` to the active tab, then returns a non-Home root to Home;
Home-root exit requires a second back within two seconds and never pops an
enclosing route. Android predictive transitions are enabled only for the active
tab while the shell is uncovered (ADR 0022), so offstage stacks cannot consume
one gesture together. Root modals retain back precedence, and visible software
IME back remains Android-owned.

Activity keeps its established portrait layout when the height available after
system insets is at least 560dp. Below 560dp, its title, SMS status and filters
scroll with the transactions; the search field remains pinned so it is always
reachable. Keyset paging and row actions stay on the same Activity provider and
list items.

## Transaction timestamps

Transaction `ts` values are UTC epoch milliseconds. Detail formatting converts
the UTC instant to device-local time and reuses the shared clock and month
formatters. Detail uses device local time while exports use the fixed `FinancialCalendar` offset (identical in India; may differ by an hour in daylight-saving zones). CSV files derive date, time, and offset from
`FinancialCalendar`; they keep existing columns in order and append `UTC Offset`
(`UTC+05:30`, for example) so a spreadsheet can interpret the local date and
time, then `UPI ID` (the stored VPA), because the Merchant column carries the
readable T-198 payee title. Manual entry starts with the current local date and time; choosing a
different date preserves the selected time of day, then `FinancialCalendar`
converts those local date and clock fields into the stored UTC instant.

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
- Parser contract version 3 shares terminal/retry decisions across live, batch
  and catch-up paths. Current-version processing errors retry once per unique
  ID in a run; the 10,000-ID failure bound produces an explicit incomplete
  result. Forced scans replace stale resume cursors while retaining completed
  version evidence and checkpoint only completed pages.
- Live identity hashes the exact sender/body with the PDU's sent timestamp.
  Inbox identity uses positive `DATE_SENT`, falling back to receipt `DATE` when
  unavailable. Receipt DATE/ID still controls keyset paging and the historical
  parser's date fallback. Missing sent time cannot guarantee live/inbox equality.
- The inbox payload carries an optional exact old receipt-hash alias. Shared
  validation resolves raw rows, transactions and dispositions before writes,
  preserves existing primary/source IDs and user facts, and abstains on
  conflicting claims. Import/catch-up preflight input pages and retain only a
  bounded last-receipt-time cohort (4,096 alias claims) across adjacent pages;
  overflow abstains until receipt time changes. Alternate mappings are
  transient, so separate runs cannot compare aliases omitted from stored state.
  See [ADR 0030](decisions/0030-sms-identity-timestamp-compatibility.md).
- The parser order is template → conservative generic parser → optional local
  LLM extractor.
- Classification separates primary OTPs from detached security footers and
  recognizes affirmative returned credits for failed payments. Negated credit
  or authorization cues remain guarded; primary OTP, promotional, failed and
  future-event evidence retains its meaning.
- `DuplicateSuppressor` links cross-source echoes only within equal known
  lifecycle states instead of deleting evidence. Existing suppressed rows are
  not automatically rewritten.

Future recurring-calendar work must route bill-due/autopay reminders to expected
events, not relax the transaction parser's future-event rejection.

### Supporting SMS (ADR 0032)

Dividend advices, RD instalment notices, EMI notices (pre-debit and debited) and
UPI collect/payment requests describe a money movement without being the
settled bank transaction. `SupportingSmsClassifier`
(`assets/seed/supporting_sms_cues_in.json`) recognizes them deterministically
and extracts amount (integer paise), source currency, account suffixes,
reference, VPA/requester and due date. `SupportingSmsLinker` then writes
`sms_transaction_links` rows, never a transaction or amount, in either arrival
order: exact paise and source-currency bucket, a time window (notices and
requests up to 7 days before the transaction; dividend and RD advices within 3
days either side), at least one corroborator (account suffix, reference,
counterparty, or a company token in the dividend narration), and exactly one
live settled canonical candidate, otherwise it abstains. `SmsIngestor` calls it
inside the existing per-message transaction (best effort; a linking failure
never fails capture), a fulfilled expected event records its origin SMS as a
link, and the nightly `linkSupportingSms` stage backfills retained messages.
`RawSmsRetention.isLinked` treats linked rows as provenance;
`TransactionSmsRepository.messagesFor` returns primary, duplicate and
supporting messages for the detail screen.

## Storage and privacy

- Drift is opened through SQLCipher.
- A generated database passphrase is protected by Android Keystore.
- `raw_sms` keeps the source SMS of transactions and dispositions (ADR 0021);
  unlinked rows expire after 7 days. Normalized transactions persist.
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
  New archives include transaction links, counterparties, category hierarchy,
  and expected-event state; older v3 archives may omit the newer optional
  tables. Restore deletes dependent rows first, restores self-references after
  their parent rows, and checks foreign-key integrity before commit.
- Delete-everything closes the database, removes DB/key/settings/import state,
  and recreates only default categories.

## Identity and categorization

`MerchantResolver` checks explicit user aliases and exact canonical names before
deterministic creation; embeddings provide review suggestions only.
`Categorizer` applies:

1. user rules;
2. optional confirmed-history memory callback;
3. the local classifier when its category threshold is met;
4. the seed keyword map;
5. a conservative person/self counterparty fallback at review confidence;
6. an optional capped LLM category suggestion;
7. `Other` at review confidence.

**Production wiring caveat (2026-09-26):** `categorizerProvider` supplies rules,
seed map, classifier and adaptive thresholds, but not the memory or LLM
callbacks. Those extension points are not evidence of active production
learning. T-177 audits and connects the needed paths. Numeric or personal VPA
shape alone does not prove non-spending or owned transfer identity.

`DecisionPolicy` chooses `auto`, `asked`, or `needs_review`. Unseen UPI
counterparties fail closed; seen counterparties rejoin the confidence policy
and can become automatic. Generic VPA extraction rejects email-domain suffixes.
Manual entries are confirmed. Category/description corrections write feedback,
rules, learned aliases, and transaction state in one database transaction.
Rules match in this order: resolved `merchant_id`, exact counterparty VPA,
exact normalized merchant identity, then the R1 word-boundary fallback for
`merchant_legacy` rules. New corrections on a resolved row create or replace a
`merchant_id` rule; its retroactive sweep selects rows by the indexed merchant
ID. Unresolved rows continue to use exact VPA or exact merchant keys. Rules
created before R3 keep their existing match types and behavior. A correction
replaces the rule for that identity, and undo restores the prior rule state.
Replacement uses a fresh opaque rule ID; its receipt requires that exact
generation and content before restoring prior mappings. Category Undo first
validates all affected transaction facts and relevant feedback membership/value
snapshots, so same-second edits or newer rules cannot be overwritten. Both
detail category entry paths reload the stored label after correction/Undo and
preserve unsaved note text.
New captures may also apply an explicit matching user rule's description;
model/memory descriptions and historical rewrites are excluded.
Confirmed rule hits use the live decision policy during history import and
catch-up. Other historical rows remain review-only. Capture-decision v2
records when a rule supplied the category.
`TransactionCorrectionController` owns the shared repository-action → undo-token
sequencing used by transaction detail and Sort; each screen supplies only its
optimistic presentation update and inverse callback.

`PayeeKey` supplies one name key and one VPA key across capture and user-label
resolution. It strips only `UPI-`, `UPI/`, `VPS*`, and `POS ` prefixes and the
trailing legal suffixes `LTD` and `LIMITED`; store numbers and city names are
preserved. VPA keys retain the PSP handle, so the same local VPA name on YBL and
Axis stays distinct. Live capture, full history import, and incremental catch-up
all use `SmsIngestor` with the same resolver. Resolution checks user VPA aliases,
user name aliases, exact canonical names, then exact legacy aliases. New
merchant IDs use the normalized name key (or full VPA key when no name exists),
and named payments also record their VPA alias for later VPA-only rows.

Ask can also use conservative brand tokens as a read-only fallback after exact
identity resolution fails. It reads only a VPA local part (never the PSP
handle). VPA local parts split on `.`, `_`, and `-`; raw merchant names also
split on whitespace. Brand tokens must contain at least four letters. Numeric,
phone-like, and mixed letter-digit gateway IDs are discarded; a local part
containing an opaque mixed token is excluded entirely. The only stripped
prefix is `pay`, backed by the `payzomato` fixture. `payu` appears as its own
gateway token in fixtures and is not stripped from words. A brand-only total
names every included VPA/raw payee and the matched word in
its answer. Non-total queries ask for clarification when brand tokens would
span payees. This path does not create merchant IDs or aliases.

Embedding similarity is review-only: it stores a suggestion in capture
provenance, leaves `merchant_id` unset, and writes no alias. Phone-number VPAs
can resolve existing user aliases but never create a merchant automatically.
Capture does not rewrite existing rows. A preview-counted, reversible backfill
for rows with `merchant_id IS NULL` and an exact user-label key/alias match is
deferred until the settings UI can show the affected history and offer Undo.
User labels still map multiple explicit aliases, preview affected history, and
refuse conflicting merges without replacing raw source fields.

## Analytics and intelligence

- `FinancialCalendar` turns local, half-open calendar days/months into UTC
  instants for SQLite queries. Dashboard periods, forecasts, anomalies,
  insights, and the Ask quota use it; tests inject the India offset around the
  local midnight/month boundary.
- `FinancialEligibility` is the shared spending contract in Drift and SQL:
  settled debit only, excluding deleted, duplicate, opted-out, and
  owned-transfer rows, and requiring a spending category (a missing or
  uncategorised category defaults to spending). Its base rule also gates
  settled credits in assistant net totals and recurring income series.
- Dashboard providers read SQL totals and grouped category, merchant, and trend
  aggregates. Transaction feeds load 100 newest rows at a time; recent cards use
  a separate six-row period query.
- Dashboard totals show the active period, the settled-spending eligibility
  rules, the known exclusion classes, and that totals cover only activity
  recorded in PaisaTrack. The dynamic exclusion amount covers settled spending
  debits marked as owned transfers or excluded from analytics; it is not a
  measure of unrecorded bank activity.
- Payment sources can be named, marked owned/active, and excluded from analytics.
  Reconciliation uses reciprocal singleton debit/credit matches across active
  owned sources, with equal amount, currency bucket and settled state inside an
  inclusive ten-minute window. It uses bounded timestamp-index probes, leaves
  ambiguous rows unlinked, and transactionally rebuilds transfer flags plus
  system-generated `transfer_leg` edges. Stale system edges are removed while
  user-authored links remain intact. A repeated reconciliation with unchanged
  evidence writes no rows. Conservatively paired transfers are excluded from
  aggregates without hiding either transaction.
- Settings has an isolated read-only Card source audit route under
  [ADR 0027](decisions/0027-read-only-card-source-audit.md). Its direct repository
  uses one read transaction, SQL source/currency/lifecycle aggregates and
  deterministic timestamp/ID candidate pages. Summaries return up to 100 sources,
  20 buckets per source and 20 observed identity conflicts; omitted coverage is
  explicit and source record totals remain complete. Candidates default to 40
  per page (maximum 100). Identifiers show only a safe four-digit suffix.
  Product/ownership remain unverified; excluded/deleted/nontransaction/duplicate
  and transfer facts stay visible. The route bypasses paymentSourcesProvider's
  load-time reconciliation and creates no source, relationship or accounting
  change. Already-collapsed historical source collisions remain unobservable.
- Recurring detection derives series from settled history. Foreground and
  nightly scans share complete projection cleanup, preserving current user
  status memory across changed IDs and temporary non-detection. Successful
  detection precedes transactional status reconciliation and stale-row pruning.
  Dashboard commitments count every active non-income INR series due in the
  current calendar month; the next-three display cap is separate. Ask applies
  the same active expense eligibility and retains source-currency buckets.
- Existing owned-transfer reconciliation requires distinct known four-digit
  account suffixes after mask normalization. Equal suffixes or missing numeric
  suffixes abstain; this conservative guard neither establishes ownership nor
  merges channel-specific sources.
- Expected-event reconciliation includes snoozed reminders at their rescheduled
  date. Exact identity/currency/amount/window, ambiguity and one-payment guards
  remain; missing identity or invalid amount stays unresolved. Updates compare
  the original state and date so cancellation or rescheduling is protected.
- `RefundLinkPreviewRepository` is a read-only preparation API with no production
  UI or ingestion caller. It uses exact stored-reference equality, source-currency
  buckets, existing spending eligibility, and bounded relationship inspection.
  Pair arithmetic supports six fractional decimal places and abstains on
  unsupported precision, ambiguity, corrupt/conflicting links or over-cap
  amounts. Source rows and monthly aggregates remain unchanged; persisted
  refund review/Undo and accounting-period policy are still open under
  [T-100](tasks/T-100.md) and [ADR 0026](decisions/0026-read-only-refund-preview.md).
- Anomaly, forecast, and insight engines are deterministic and consume the
  same eligibility contract as Dashboard.
- The anomaly minimum amount floor is denominated in INR. Other currencies are
  not floor-suppressed because PaisaTrack does not infer exchange rates.
- Nightly work purges expired unlinked raw SMS, refreshes recurring/baseline/classifier
  state, and recomputes insights with checkpoints.

## Insight claim contract

Deterministic insight rows store a versioned claim envelope at
`insights.payload_json.claim`; this reuses the existing JSON column and adds no
schema. The envelope identifies the calculation version and stable `claim_id`,
records `basis: observed`, scope, comparable date windows, numeric metrics,
coverage, and a stable input hash over every scope-matched evidence row,
including its identity, amount, category, currency, timestamp, direction, and
financial eligibility fields. Evidence IDs are sorted and capped at 50;
`total_count`, `truncated`, and the full evidence digest retain the full scope.

Supported calculations are category deltas, recorded fees, duplicate
subscriptions, recurring price changes, and missed autopay. Category deltas
compare equal elapsed local days for partial months; a zero previous total
abstains. Currency buckets remain separate, including unknown currency.
Coverage counts unreviewed rows, unknown currencies, and exclusions for
unsettled rows, owned transfers, analytics exclusions, non-spending categories,
and credits. Refunds remain gross recorded debits because production refund
links are not implemented.

`ClaimValidator` rejects malformed/unknown claims and inconsistent category
arithmetic. `ClaimRenderer` supplies all visible insight and assistant text from
typed fields; payload prose is ignored. Both dashboard and Trends hide legacy,
anomaly, forecast, and stale claims. A read checks the hash for each displayed
claim's recomputed scope, so an edit hides it until `DerivedReadsService` recomputes
it. “Why?” opens Activity filtered to the cited IDs and labels truncated
evidence as “showing 50 of N”. Dismissal stays on the stable claim row ID across
recomputation. Free-text narrative generation is removed; T-178c may add
closed-set claim selection.

Ask resolves a merchant phrase against canonical names, user labels, aliases,
and captured payee evidence using whole-phrase token boundaries. A resolved
payee filters eligible rows by merchant ID, its VPA keys, or its normalized
name keys. Unresolved phrases fall back to whole-token matching against raw
merchant text; multiple matching payees return a clarification instead of a
combined or guessed total. Financial eligibility and currency buckets remain
the same as other Ask totals.

Trends can be empty when no supported, fresh claim exists for the selected
period; aggregate charts may still have data.

The Trends inbox lifecycle is specified in
[trends-inbox.md](specs/trends-inbox.md). When enabled, it derives items only
from valid, fresh claims rendered by `ClaimRenderer`; identity combines kind,
scope, and calendar period. Per-item `new`/`seen`/`moved`/`cleared` state and
the last validated snapshot live in the existing `model_meta` key-value table
under `trends_inbox_v1`, without a schema change. A claim that stops qualifying
remains only for deduplication and Undo; it is not rendered or counted and has
no stale drill-down. Items are retained for the current period and its previous
three periods, including while a historical period is selected. New items
become seen when the user leaves Trends or backgrounds the app, not during the
first build. Claim-level `insights.dismissed` maps to `cleared`. Corrupt or
unsupported-version metadata is backed up under
`trends_inbox_v1_backup` before repair. The existing Trends claim feed remains
available behind the `inboxEnabled` rollback switch. All state is local; inbox
items contain no SMS text and do not trigger system notifications.

Current boundaries that must be preserved while fixing the UI:

- SQL aggregates are the only valid source for full-period totals. A loading or
  failed aggregate must not fall back to the bounded 100-row Activity feed.
- Current-month budget guidance is not valid for a historical/custom period.
- Empty financial state is shown only after a successful empty query; loading
  and failure remain distinct states.
- The global monthly-budget/merchant-cap implementation is a prototype stored
  in `baselines`, not the planned category-budget domain.

Known scale concerns include bounded feed/review queries (verify full-history
search and queue paging separately), owned-transfer candidate work proportional
to rows in each ten-minute timestamp window, and bounded legacy in-memory
backup compatibility helpers. Payee evidence
aggregation already uses the SQL index described above. The production document path
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
Category filters resolve against the stored taxonomy: a parent includes its
descendants, an exact child stays narrow, and explicitly named categories are
queried together. Unrelated or duplicate-name ambiguity is refused before
merchant lookup. Spending totals use settled, non-excluded transactions in
spending categories, matching dashboard eligibility. Category typo-tolerance
and arbitrary fuzzy matching remain unsupported.

## Future extension boundaries

- T-102: import statements through preview, fingerprinting, and reconciliation;
  do not bypass `SmsIngestor` invariants when creating normalized rows.
- T-100: represent transaction relationships; do not mutate/delete originals.
- T-101: store expected events separately from transactions.
- Expected events auto-fulfil only against one eligible settled debit with an
  exact normalized VPA, matching amount/range, and an in-window timestamp.
  Missing identity or ambiguous candidates stay expected for review; repeated
  reminders cannot reopen terminal event states.
- T-098: compute budgets from the shared net-spending contract.

See `docs/schema.md`, `docs/privacy.md`, and ADRs before changing these boundaries.

## Remaining assistance and AI work

The [smart assistance plan](plans/smart-transaction-assistance.md) and
[AI report](reports/grounded-ai-opportunities.md) extend existing components.
They describe the remaining work. [ADR 0011](decisions/0011-evidence-backed-assistance.md)
separates source facts, user-confirmed labels, suggestions, and forecast estimates;
requires scoped correction/undo; and limits model output to supported claims.
Current SQL arithmetic, evidence preservation and offline fallback remain the
boundaries. No new tables, model, runtime or dependency are introduced here.

### Future importers (T-164e contract)

There is no statement or CSV importer yet. Any importer must parse date-only
values as local calendar days through `FinancialCalendar` (never as UTC
midnight instants), keep source clock times when present, and store UTC
epoch milliseconds like SMS capture and manual entry.
