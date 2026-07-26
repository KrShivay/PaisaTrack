# SMS Intelligence — Target Design

Status: proposal (2026-07-26). Not yet accepted; no ADR supersedes anything here.

This document designs the end-to-end path from an on-device SMS to a
trustworthy, explainable financial record and the insights built on top of it.
It is **gap-driven**: it audits the shipped pipeline first, then specifies only
what must change. Where the current implementation is already correct, it says
so and stops.

Scope decisions taken with the product owner (2026-07-26):

- **Numeric truth is never model-generated.** Amounts, direction, and dates come
  only from deterministic extraction over stored source text. Models may infer
  *descriptive* detail — merchant identity, description, category, subscription
  or EMI nature, context — under confidence thresholds with user correction.
- **India-first, extensible.** UPI/IMPS/NEFT/RuPay/INR and Indian DLT sender
  headers are the design centre; locale-specific knowledge lives in data, not
  code, so a second market is a fixture change.
- **All three feature tiers, phased**: truth layer → commitments → insight.
- No cloud inference path (ADR 0002) and no telemetry. Every evaluation number
  in this document is produced on-device or from sanitized fixtures in-repo.

---

## 1. Current state (verified against source, 2026-07-26)

| Stage | Implementation | Verified in |
|---|---|---|
| Native admission | `SmsFilter` allowlists 27 DLT sender tokens, then drops OTP-shaped and promotional bodies lacking a settled verb. Content-free drop counters only. | `android/app/src/main/kotlin/com/paisatrack/capture/SmsFilter.kt` |
| Ingestion | `SmsIngestor` shared by live `EventChannel` and paged history import; deterministic `txn_<smsId>` primary key gives same-message idempotency. | `lib/capture/sms_ingestion.dart` |
| Parsing | `ParserCascade`: template (confidence 0.97) → `GenericTransactionParser` (0.5–0.6) → `LlmExtractor` (capped 0.75). | `lib/capture/parser_cascade.dart` |
| Templates | 8 bank files (`axisbk`, `centbk`, `hdfcbk`, `icicib`, `indusind`, `kotak`, `paytmb`, `sbi`) with named capture groups normalized by `FieldNormalizer`. | `assets/templates/` |
| Dedup | `DuplicateMatchRule`: same direction, amount within ₹0.005, timestamps within 10 minutes, matching ref id **or** counterparty key. Writes `duplicate_of_txn_id`, never deletes. | `lib/data/dedup/duplicate_match_rule.dart` |
| Identity | `MerchantResolver`: exact normalized alias → brute-force cosine over the full merchant table (auto-link ≥0.92, review ≥0.75) → create new merchant. | `lib/enrichment/merchant_resolver.dart` |
| Categorization | `Categorizer` ladder: user rule (1.0) → `LocalClassifier` (adaptive threshold, default 0.8) → seed keyword map (0.8) → `other` (0.3). | `lib/enrichment/categorizer.dart` |
| Decision | `DecisionPolicy`: silent ≥0.90; ask ≥0.60 when amount ≥₹500 or merchant seen ≥3× and daily ask budget (2) remains; else `needs_review`. Unseen UPI counterparties fail closed. | `lib/enrichment/decision_policy.dart` |
| Adaptation | `AdaptiveThresholdPolicy` raises a category threshold by 0.03 when >15% of the last 50 labels were corrected, else lowers by 0.01. | `lib/enrichment/decision_policy.dart` |
| Recurrence | `RecurringDetector`: ±5% amount tolerance, gap coefficient of variation ≤0.25, 20% missed grace. Deterministic, nightly. | `lib/intelligence/recurring_detector.dart` |
| Anomalies | `AnomalyDetector`: 2.5σ over ≥8 baseline periods, weekly by category and monthly by merchant. | `lib/intelligence/anomaly_detector.dart` |
| Storage | Drift over SQLCipher at schema v7; Android Keystore-wrapped passphrase; `raw_sms` retained 30 days. | `docs/schema.md`, `lib/core/constants.dart` |

This is a strong base. Precision-first design, evidence preservation, fail-closed
defaults, and the no-cloud boundary are all already load-bearing. The gaps below
are structural, not quality problems.

---

## 2. Structural gaps

### G1 — The LLM can author financial truth

`LlmExtractor` returns a full `NormalizedTransactionRecord` including `amount`,
`direction`, and `ts`. Validation checks *plausibility* (positive, finite, date
within range) but never checks that the value **appears in the message**. A model
that reads `Rs.1,250` and emits `12500` produces a schema-valid, plausible,
persisted ₹12,500 expense at confidence 0.75.

This is the one invariant the product owner named explicitly, and it is currently
unenforced. It is the highest-priority change in this document.

### G2 — `status` conflates labelling confidence with financial state

`transactions.status` holds a `DecisionStatus` (`auto` / `asked` /
`needs_review`) — how sure we are about the *label*. There is nowhere to record
what the bank actually did: authorised-not-settled, failed, declined, reversed,
expected-but-not-yet-charged.

The consequence is visible in `GenericTransactionParser._hardReject`, which
discards any message containing `failed`, `declined`, `unsuccessful`, `is due`,
`due on`, `requested`, `cashback`, `against reversal`, `interest credit`, or
`statement`. Because there is no lifecycle state to put them in, the only safe
action is to throw them away. Every feature the brief asks for — pending, failed,
refunds, reversals, upcoming bills — is blocked on this single column split.

### G3 — Transactions are single-message; real events are multi-message

The `txn_<smsId>` primary key hard-codes one SMS to one transaction. A card
purchase abroad is authorisation → settlement (often 1–3 days apart, sometimes a
different amount). An EMI is mandate registration → monthly debit. A refund is
merchant confirmation → bank credit. A failed UPI is debit → auto-reversal within
minutes to days.

`duplicate_of_txn_id` and `ownedTransferId` are two special-cased relationships
bolted onto a model that has no general notion of "these messages describe one
financial event". `DuplicateSuppressor`'s 10-minute window cannot span an
auth→settle gap, and its counterparty comparison uses substring `contains`, which
matches `AMAZON` to `AMAZONPAYLATER` (the same over-matching already filed
against rules).

### G4 — Merchant identity fragments on UPI noise

`MerchantResolver.normalizeAlias` is `uppercase → strip non-alphanumeric`. So
`paytm-9876543210@ptys` becomes `PAYTM9876543210PTYS` — unique per counterparty
phone number. Every person you pay, and every dynamic merchant QR, mints a new
merchant row and a new review item. Device testing on 2026-07-17 recorded 6,807
review rows across 2,467 merchants on a single install; this normalization is the
mechanical cause, and it is what makes T-117 and T-123 hard.

The resolver also cannot distinguish a *person* from a *merchant*. People should
never be categorization candidates at all — they are transfers or P2P, not
"Food & Dining" — yet they enter the same ladder and bottom out at `other` at
confidence 0.3, which is exactly the value that guarantees a review row.

### G5 — Admission is a silent, unmeasurable recall ceiling

27 sender tokens gate everything. An unlisted bank, a renamed DLT header, or a
new fintech is dropped in Kotlin with only an in-memory counter that resets on
process death. The user is never told; the app simply under-reports spending
while looking complete. T-129 and T-108 recognise the measurement half of this;
the design half — that sender identity should be a *confidence input*, not a
*gate* — is unaddressed.

### G6 — No expected/future obligations

Bill-due and autopay-reminder messages are hard-rejected. There is no store for
"₹1,499 expected from Netflix around the 12th". Recurrence is derived only
backwards from settled history, so a first-ever bill is invisible until after it
is paid, and a *missed* payment cannot be detected because nothing was expected.

### G7 — Category signal is thin

`LocalClassifier` is a linear softmax over 16 embedding dimensions plus log-amount,
hour, weekday, and channel index. It has no merchant-frequency prior, no
user-correction memory beyond the rules table, and no notion of the strongest
available signal — *what this specific merchant was labelled last time*. The seed
keyword map beneath it is a static JSON lookup.

---

## 3. Approach evaluation

Five candidate strategies, scored for this problem (Indian bank SMS, on-device,
privacy-hard, no telemetry, single-developer maintenance budget).

| | Deterministic templates | Grammar / rule cascade | Classical ML | On-device LLM | **Hybrid (recommended)** |
|---|---|---|---|---|---|
| Numeric precision | Highest | High | N/A | **Unacceptable** | Highest — verification layer |
| Recall on unseen formats | Very low | Moderate | N/A | High | High |
| Explainability | Total | Total | Partial | None | Total for money, partial for labels |
| Cost per new bank | 1 fixture + 1 regex | 0 (often) | 0 | 0 | 0–1 fixture |
| Failure mode | Silent miss | Silent miss | Confident wrong label | **Confident wrong number** | Miss → review queue |
| Runtime cost | ~µs | ~µs | ~ms | ~0.5–3 s, ~500 MB | Amortised: LLM rare |
| Offline | Yes | Yes | Yes | Yes | Yes |
| Maintenance | High, linear in banks | Moderate | Low | Low | Moderate |

**Conclusion.** No single strategy is adequate. Templates give the precision the
product's credibility depends on but cannot keep up with sender churn. An LLM
gives the recall templates lack but has exactly the wrong failure mode for money:
it fails *confidently* and *numerically*. Classical ML is useless for extraction
and genuinely good for categorization, which is where it should live.

The recommended architecture keeps all four but assigns each a job it cannot fail
at catastrophically, separated by an explicit verification boundary.

---

## 4. The Numeric Trust Boundary

> **Invariant.** Every monetary amount, direction, and timestamp persisted to
> `transactions` must be reproducible by re-running a deterministic normalizer
> over a byte range of stored source text. No component that cannot cite a span
> may write these fields.

This is enforceable, testable, and cheap. It reduces to a type:

```dart
/// A field value together with the exact source substring it came from.
class FieldEvidence {
  final String field;        // 'amount' | 'direction' | 'ts' | 'account' ...
  final int start;           // byte offset into the source body
  final int end;
  final String verbatim;     // body.substring(start, end) — asserted, not trusted
  final String extractor;    // 'template:hdfc_upi_debit_v1' | 'grammar' | 'llm_span'
}
```

`NormalizedTransactionRecord` gains `List<FieldEvidence> evidence`. A repository
write is rejected — loudly, in debug; to `needs_review`, in release — unless
`amount`, `direction`, and `ts` each carry evidence whose `verbatim` still equals
`body.substring(start, end)` and whose re-normalization through `FieldNormalizer`
yields the same value.

### What this does to the LLM

`LlmExtractor` stops returning a record and becomes **`LlmFieldLocator`**: it
returns *quotations*, not values.

```json
{
  "amount_text":    "Rs.1,250.00",
  "direction_text": "debited",
  "date_text":      "26-07-26",
  "merchant_text":  "SWIGGY INSTAMART",
  "account_text":   "XX4412",
  "message_kind":   "settled_debit"
}
```

`SpanVerifier` then requires each quoted string to occur **verbatim** in the body,
resolves it to offsets, and hands the substring to the same `FieldNormalizer` the
templates use. A hallucinated `12500` is not in the body and the record is
refused. A correctly located `Rs.1,250.00` is parsed by deterministic code that
templates already trust.

This preserves the LLM's real value — it is genuinely good at *finding* fields in
prose it has never seen — while making numeric hallucination structurally
impossible rather than statistically unlikely.

### What the model is still allowed to author

Per the product owner's decision, inferred **descriptive** detail is permitted:

| Model may produce | Constraint |
|---|---|
| Cleaned merchant name (`SWIGGYINSTAMART9821` → `Swiggy Instamart`) | Stored in `merchants.inferred_name`, never overwriting `merchant_raw`; user-correctable |
| Category suggestion | Must clear the category threshold; otherwise review |
| One-line description / context | Display only; never an aggregate input |
| Message-kind hint (subscription, EMI, refund, reminder) | A *hint* into the lifecycle classifier, never the sole basis for a state change |
| Narrative summaries over already-computed aggregates | Existing `NarrativeInsightGenerator` contract — numbers interpolated from SQL, prose from the model |

Everything in that table is a **label**: wrong is annoying and one tap to fix.
Everything above the boundary is **evidence**: wrong is a corrupted ledger.

---

## 5. Target pipeline

```
L0  Admission        native shape triage + sender scoring, content-free counters
L1  Classification   message kind: settled | pending | failed | reversal
                     | reminder | mandate | balance | statement | promo | otp
L2  Extraction       template → grammar cascade → LLM span proposal
L3  Verification     ══ NUMERIC TRUST BOUNDARY ══  span re-anchor + normalize
L4  Identity         payment source · counterparty · merchant cluster
L5  Correlation      event key → link graph (echo, settle, reverse, refund, transfer)
L6  Lifecycle        financial state machine
L7  Enrichment       category · tags · recurrence · commitments   [AI permitted]
L8  Analytics        net-spending contract → budgets · trends · insights
```

Mapping to today: L0 exists but over-gates (G5); L1 does not exist and is
smeared across L0's reject lists and L2's `_hardReject` (G2); L2 exists; L3 does
not exist (G1); L4 exists but fragments (G4); L5 is a 10-minute special case
(G3); L6 does not exist (G2); L7 exists and is thin (G7); L8 exists and is the
strongest layer.

### L0 — Admission, restated

Sender identity becomes a **prior**, not a gate.

```
admit(sender, body):
  senderClass = allowlisted | dlt_shaped | numeric | unknown
  shapeScore  = currency token  (+2)
              + settled/pending/failed verb  (+2)
              + account/card/VPA token  (+1)
              + reference/UTR token  (+1)
  if otpShape(body) and not settledVerb: reject('otp')
  if senderClass == numeric and shapeScore < 5: reject('personal_sender')
  if shapeScore >= 4: admit(trustPrior(senderClass))
  if shapeScore >= 2: quarantine()        // visible, counted, never silent
  reject('below_shape_floor')
```

Quarantined messages are stored as `raw_sms` with `admission = 'quarantined'`,
surfaced in a *"Messages we couldn't read"* screen with per-sender counts, and
retried automatically after a template or parser upgrade (`retry_version`,
which T-129 already needs). Rejection reasons are content-free codes so they can
be counted durably without ever persisting a body.

The privacy cost is bounded and worth stating plainly: the shape test runs
in-process over messages the app is already permitted to read, non-matching
bodies are never persisted, and quarantine inherits the same 30-day retention as
`raw_sms`.

### L1 — Message classification

A small deterministic classifier over cue phrases, keyed by locale pack, that
assigns exactly one `MessageKind` before extraction:

| Kind | Cues (India pack) | Produces |
|---|---|---|
| `settledDebit` | debited, spent, paid, withdrawn, purchase of | transaction (settled) |
| `settledCredit` | credited, received, deposited | transaction (settled) |
| `pendingAuth` | authorized, blocked, on hold, temporarily | transaction (pending) |
| `failed` | failed, declined, unsuccessful, could not be processed | transaction (failed) |
| `reversal` | reversed, reversal, refunded to, credited back | link candidate |
| `reminder` | is due, due on, will be debited, autopay scheduled, e-mandate | **expected event** |
| `mandate` | mandate registered, standing instruction, subscription activated | commitment |
| `balance` | avl bal, available balance (with no settled verb) | balance snapshot only |
| `statement` | statement generated, min due, total due | statement metadata |
| `promo` / `otp` | existing markers | rejected with reason code |

This is the piece that unblocks G2 and G6 at once. It is deterministic, it is
cheap, and the fixture corpus to test it already exists (`test/fixtures/sms/`
already contains `axisbk_bill_due_reminder.txt`,
`axisbk_txn_declined_international_disabled.txt`, and
`axisbk_statement_generated.txt` — currently only as negative cases).

---

## 6. Data model

All changes are additive, in the repo's established style: new nullable columns
with defaults, new tables, migration tests from the previous version, and no
destructive rewrite of evidence.

### 6.1 Split the overloaded `status` (schema v8)

```sql
-- transactions
ALTER TABLE transactions ADD COLUMN lifecycle_state TEXT NOT NULL DEFAULT 'settled';
ALTER TABLE transactions ADD COLUMN lifecycle_reason TEXT;          -- content-free code
ALTER TABLE transactions ADD COLUMN message_kind    TEXT;           -- L1 output
ALTER TABLE transactions ADD COLUMN event_id        TEXT;           -- FK financial_events
ALTER TABLE transactions ADD COLUMN evidence_json   TEXT;           -- List<FieldEvidence>
ALTER TABLE transactions ADD COLUMN counterparty_id TEXT;           -- FK counterparties
CREATE INDEX idx_transactions_lifecycle ON transactions(lifecycle_state);
CREATE INDEX idx_transactions_event ON transactions(event_id);
```

`status` keeps its meaning and its name is clarified in code as
`labelStatus` — renaming the column itself is a v9 concern and must go through
`rename`, not find-and-replace (CLAUDE.md).

Backfill: every existing row is `lifecycle_state = 'settled'`, which is exactly
what today's semantics already assume. Existing analytics predicates keep working
unchanged because they filter on `is_deleted`, `duplicate_of_txn_id`,
`owned_transfer_id`, and `is_analytics_excluded` — none of which move.

### 6.2 Financial events and links

```sql
CREATE TABLE financial_events (
  id            TEXT PRIMARY KEY,
  event_key     TEXT NOT NULL,          -- see §7.2
  key_basis     TEXT NOT NULL,          -- 'ref' | 'auth' | 'echo' | 'manual'
  kind          TEXT NOT NULL,          -- 'purchase'|'transfer'|'refund'|'withdrawal'|'emi'|'fee'
  net_amount    INTEGER NOT NULL,       -- paise; the single number analytics reads
  currency      TEXT NOT NULL DEFAULT 'INR',
  opened_at     INTEGER NOT NULL,
  closed_at     INTEGER,
  state         TEXT NOT NULL,          -- mirrors the dominant transaction lifecycle
  confidence    REAL NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_financial_events_key ON financial_events(event_key);

CREATE TABLE transaction_links (
  id          TEXT PRIMARY KEY,
  from_txn_id TEXT NOT NULL REFERENCES transactions(id),
  to_txn_id   TEXT NOT NULL REFERENCES transactions(id),
  link_type   TEXT NOT NULL,   -- echo|settles|reverses|refunds|repays|transfer_leg|fulfills
  confidence  REAL NOT NULL,
  basis       TEXT NOT NULL,   -- 'ref_id' | 'auth_window' | 'amount_time' | 'user'
  created_by  TEXT NOT NULL,   -- 'system' | 'user'
  created_at  INTEGER NOT NULL
);
CREATE INDEX idx_links_from ON transaction_links(from_txn_id);
CREATE INDEX idx_links_to   ON transaction_links(to_txn_id);
```

`duplicate_of_txn_id` and `owned_transfer_id` remain as **materialized fast
paths** — the link graph is the source of truth, those columns are a denormalized
projection maintained in the same write transaction. This preserves every
existing query and index while generalizing the model. ADR 0003's guarantee that
suppression never deletes evidence is strengthened, not weakened: a link row
records *why*.

### 6.3 Counterparties, separate from merchants

```sql
CREATE TABLE counterparties (
  id             TEXT PRIMARY KEY,
  kind           TEXT NOT NULL,   -- 'merchant' | 'person' | 'self' | 'institution' | 'unknown'
  identity_key   TEXT NOT NULL,   -- structured key, see §8
  display_name   TEXT,
  inferred_name  TEXT,            -- model-authored, correctable, never overwrites raw
  psp_family     TEXT,            -- 'ybl'|'okaxis'|'paytm'|... for VPA counterparties
  merchant_id    TEXT REFERENCES merchants(id),   -- only when kind='merchant'
  first_seen     INTEGER NOT NULL,
  last_seen      INTEGER NOT NULL,
  txn_count      INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX idx_counterparties_identity ON counterparties(identity_key);
```

This is the fix for G4. A person you pay is a `counterparty` with `kind='person'`
and **no merchant row**, so they never reach the categorization ladder and never
generate a review item — they default to a P2P/Transfer treatment. Only
`kind='merchant'` promotes into `merchants` and participates in embedding
clustering.

### 6.4 Expected events (commitments)

```sql
CREATE TABLE expected_events (
  id                TEXT PRIMARY KEY,
  source            TEXT NOT NULL,   -- 'reminder_sms'|'mandate_sms'|'detected_series'|'user'
  origin_sms_id     TEXT REFERENCES raw_sms(id),
  series_id         TEXT REFERENCES recurring_series(id),
  counterparty_id   TEXT REFERENCES counterparties(id),
  label             TEXT NOT NULL,
  expected_amount   INTEGER,         -- paise; NULL when the message gives a range
  amount_low        INTEGER,
  amount_high       INTEGER,
  expected_date     INTEGER NOT NULL,
  date_window_days  INTEGER NOT NULL DEFAULT 3,
  cadence           TEXT,            -- 'monthly'|'quarterly'|'annual'|'weekly'|'once'
  state             TEXT NOT NULL,   -- 'expected'|'fulfilled'|'missed'|'cancelled'|'snoozed'
  fulfilled_txn_id  TEXT REFERENCES transactions(id),
  confidence        REAL NOT NULL,
  dedup_key         TEXT NOT NULL,   -- obligation identity; repeated reminders collapse
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_expected_dedup ON expected_events(dedup_key, expected_date);
```

Expected events are **never** transactions and never enter any spending
aggregate. They are a forecast surface. This satisfies the existing architecture
constraint that future-event SMS must not relax the transaction parser
(`docs/architecture.md`) and gives T-101 its store.

### 6.5 Monetary representation

`transactions.amount` is `REAL` (Dart `double`), and T-130 already flags the risk.
Every new monetary column in this design is `INTEGER` **paise**. The migration of
the existing column is a separate, staged concern (T-130), but new surfaces must
not add to the debt. `DuplicateMatchRule`'s ₹0.005 tolerance exists precisely
because of float comparison; in paise it becomes exact equality.

---

## 7. Lifecycle and correlation

### 7.1 Transaction lifecycle state machine

```
                    ┌──────────────┐
                    │   expected   │  (from expected_events, not a transaction)
                    └──────┬───────┘
                           │ matching debit observed
                           ▼
  pendingAuth ────────► settled ◄──────── settledDebit / settledCredit
      │  │                 │
      │  │                 │ reversal message links back
      │  │                 ▼
      │  │              reversed
      │  └── expiry (no settle within N days) ──► expired
      │
      └── failure message links ──► failed

  failed ──► (terminal, excluded from all spending aggregates)
  reversed ──► (net effect zero; both rows visible, event net_amount = 0)
```

Rules:

- Only `settled` and `pending` rows can appear in a spending total, and `pending`
  is included **only** in a clearly-labelled "including pending" view — never in
  budgets or in the headline monthly figure by default.
- `failed` and `reversed` never consume budget. They stay visible with an
  explanation, honouring the "preserve evidence, never silently delete" constraint
  in PLAN.md.
- `pendingAuth` that receives no settlement within `authExpiryDays` (default 7,
  configurable per channel; card holds abroad can run longer) transitions to
  `expired` and is dropped from totals with a review-queue note rather than
  deleted.
- Every transition writes a row to `feedback`-style provenance so the trail is
  reconstructible.

### 7.2 Event correlation keys

Ordered, highest-trust first. The first key that produces a match wins; failure
to match is never an error, it just leaves the transaction as its own event.

| Priority | Key | Form | Window | Use |
|---|---|---|---|---|
| 1 | `ref` | `ref:<normalized UTR/RRN/txn id>` | ±30 d | Strongest. Exact, bank-issued. Fixes auth→settle across days. |
| 2 | `auth` | `auth:<card_last4>|<merchant_norm>|<amount_paise ±2%>` | ±5 d | Card authorization → settlement, incl. FX-adjusted amounts. |
| 3 | `reversal` | `rev:<counterparty_key>|<amount_paise>` opposite direction | ±30 d | Refunds and auto-reversals. |
| 4 | `echo` | `echo:<direction>|<amount_paise>|<counterparty_key>` | ±10 min | Existing cross-source dedup; unchanged semantics. |
| 5 | `transfer` | debit+credit between two owned sources, same amount | ±60 min | Existing owned-transfer pairing. |

Two corrections to today's matcher are required:

1. **Counterparty comparison must stop using substring `contains`.**
   `DuplicateMatchRule._sameCounterparty` returns true when either key contains
   the other, so `AMAZON` matches `AMAZONPAYLATER`. Replace with exact match on
   the structured identity key (§8), falling back to a normalized-prefix rule
   with a minimum length and an explicit token boundary. Same defect, same fix as
   the rules-matching item already on the board.
2. **Ref-id normalization.** Banks pad, prefix, and case UTRs inconsistently
   (`UPI/123456789012`, `Ref 123456789012`, `utr123456789012`). Normalize to the
   longest digit run of length ≥ 9 before comparing, and never match on a ref
   shorter than 6 characters.

### 7.3 Refunds, reversals, and net spending

A refund is a `reverses` or `refunds` link between a credit and an earlier debit.
Matching is **suggested, never silent**:

- Confidence ≥ 0.90 (exact ref match, or exact amount + same counterparty within
  30 days with no other candidate) → auto-link, shown with a "linked
  automatically — undo" affordance.
- 0.60–0.90, or more than one candidate → a review card offering the ranked
  candidates. Fail closed: unlinked.
- Partial refunds link with an explicit `amount` on the link row; many refunds
  may link to one expense.

`financial_events.net_amount` becomes the single number every aggregate reads —
this is the "shared net-spending contract" that T-126 and T-098 both depend on.
Budgets, trends, category totals, and the assistant all consume it, so a refund
reduces spending in exactly one place with exactly one definition.

### 7.4 Cash withdrawals and transfers

- **ATM withdrawal** is `kind='withdrawal'`, not an expense. It moves money from
  a tracked source to untracked cash. Default: excluded from category spending,
  shown in a separate "Cash" line, with an optional prompt to split it into cash
  expenses later. Counting withdrawals as spending double-counts anyone who then
  records cash purchases manually.
- **Self-transfers** between owned sources are already excluded via
  `owned_transfer_id`; that logic moves behind the link graph unchanged. The
  O(n²) reconciliation scan T-130 flags is replaced by an indexed SQL join on
  `(amount_paise, ts bucket, direction)`.
- **Credit-card bill payment** is the subtle case: it is a transfer (bank →
  card), and the card's individual purchases are the real expenses. Counting both
  double-counts. Detect via `kind='institution'` counterparty + card payment
  cues, classify as `transfer_leg`, and exclude — with a clear explanation, since
  this is the single most confusing exclusion for users.

---

## 8. Identity resolution

### 8.1 Structured counterparty keys

Replace the flat `uppercase + strip` alias with a parse:

```
VPA  9876543210@ybl              → {kind: person,   core: <phone-hash>, psp: ybl}
VPA  swiggy.stores@icici         → {kind: merchant, core: SWIGGYSTORES, psp: icici}
VPA  paytmqr2810050501011x@paytm → {kind: merchant, core: <qr-opaque>,  psp: paytm}
Card SWIGGY INSTAMART BANGALORE  → {kind: merchant, core: SWIGGYINSTAMART, geo: BANGALORE}
```

Rules, in order:

1. Strip a trailing digit run of length ≥ 6 from the VPA local part — that is a
   phone number, not an identity. `paytm-9876543210` → `paytm`… but only when the
   remaining core is itself a known PSP token, otherwise the whole local part is
   the identity. (Getting this backwards is how `PAYTM` swallows every Paytm
   user; the PSP-token check is what prevents it.)
2. Classify `kind`: a local part that is *only* digits, or that matches
   `<name><10-digit>`, is a **person**. Known aggregator QR prefixes
   (`paytmqr`, `bharatpe`, `q`, `merchant`, `mab`) are **merchant**, opaque core.
   Anything matching the seed merchant vocabulary is **merchant**.
3. Strip trailing geography and store-number tokens from card descriptors
   (`SWIGGY INSTAMART BANGALORE`, `RELIANCE SMART 4471`) — these fragment one
   merchant into dozens.
4. Only then apply the existing embedding cosine search, and only within
   `kind='merchant'`.

Expected effect: a large drop in merchant rows per 1,000 transactions, since P2P
counterparties stop minting merchants entirely. The baseline must be measured
before the change rather than assumed — 2,467 merchants is a known count, but the
transaction count it came from was not recorded, so §13.2's target is stated as a
ratio to be established by T-143 first.

### 8.2 Merchant clustering and bulk correction

Even with better keys, some fragmentation remains. Add an offline (nightly)
**agglomerative pass** over merchant embeddings at a *lower* threshold than the
online auto-link 0.92 — cluster at ≥0.85, but present clusters as *suggestions*
in the Payee Labels screen rather than merging automatically. One tap merges a
cluster, relabels history via the existing preview-and-reversible label
machinery, and teaches a rule.

This converts T-117's and T-123's problem from "paginate thousands of rows" into
"resolve a much smaller set of clusters", and it reuses the preview-and-reverse
label safety already built. Their paging work stays necessary — it just stops
being the only mitigation.

### 8.3 Categorization ladder, revised

```
1. user rule                                        confidence 1.00
2. merchant memory  — the user's own last confirmed
   label for this merchant, with Laplace-smoothed
   agreement across ≥2 confirmations              0.95 · agreement
3. local classifier (upgraded features)            model probability
4. LLM category suggestion  [model-authored]       capped 0.70
5. seed keyword map                                0.80
6. other                                           0.30
```

Step 2 is new and is likely the single largest accuracy gain available: the
strongest predictor of how a user categorizes a merchant is how they categorized
it last time, and today that signal only exists if it happened to be promoted to
a rule. Step 4 is new and is where the product owner's "details may be inferred"
allowance is spent — capped below the 0.90 silent threshold so an LLM category
can never auto-apply without either a rule, a confirmation, or corroboration.

Classifier feature upgrade (step 3): raise embedding dimensions 16 → 64, add
merchant transaction count, days-since-last-seen for this merchant, amount
z-score *within this merchant*, is-round-amount, day-of-month, and channel
one-hot instead of the current ordinal `channel.index / n` — an ordinal encoding
of an unordered enum is actively misleading to a linear model.

---

## 9. User-facing capabilities

Grouped by the three tiers the product owner selected, in dependency order. Each
entry names what it needs from the layers above.

### Tier 1 — Truth layer (foundation; everything else is unreliable without it)

| Capability | Needs | Behaviour |
|---|---|---|
| **Pending / failed transactions** | L1, L6 | Failed and declined payments appear, greyed, excluded from totals, with "this didn't go through". Pending card holds show in an opt-in "including pending" view. Today both are silently discarded. |
| **Refunds and reversals** | L5, §7.3 | The credit links to the original expense; the category total drops by the refunded amount; both rows stay visible with the relationship explained. Partial and multiple refunds supported. |
| **Duplicate suppression across sources** | L5 | Existing behaviour, generalized: bank alert + PhonePe alert for one payment collapse to one event, with the second visible as evidence. |
| **Cash withdrawals** | §7.4 | Separate "Cash" treatment, not a category expense. Optional later split into cash spends. |
| **Transfers (self, P2P, card bill)** | §7.4, L4 | Owned-source transfers and credit-card bill payments excluded from spending with an explanation; P2P to people categorized as transfers, not merchant spend. |
| **Merchant recognition** | L4, §8 | Structured identity keys + cluster suggestions. "Swiggy" is one merchant, not eleven. |
| **Unread-message visibility** | L0 | "Messages we couldn't read" with per-sender counts and a one-tap fixture donation path (existing sanitizer). Turns a silent recall ceiling into a measurable one. |

### Tier 2 — Commitments and recurrence

| Capability | Needs | Behaviour |
|---|---|---|
| **Recurring bills and EMIs** | L7, §6.4 | Existing detector plus forward-looking expected events. EMIs distinguished from subscriptions by fixed-amount + fixed-tenure + `institution` counterparty. |
| **Subscriptions** | L7 | Detected from cadence + merchant class + mandate messages. Surfaces total monthly subscription load, a genuinely popular number nobody computes for themselves. |
| **Upcoming payment calendar** | L1 `reminder`, §6.4 | Bill-due and autopay reminders become expected events with a date window and amount range. Repeated reminders for one obligation collapse via `dedup_key`. |
| **Missed payment detection** | §6.4 | An expected event with no matching debit past its window becomes `missed` — impossible today, because nothing is ever expected. |
| **Price-change alerts** | L7 | A recurring series whose amount moves beyond ±5% tolerance raises a "Netflix went from ₹649 to ₹799" insight. The detector already tracks `amountTrend`; it needs a surface. |
| **Duplicate subscription detection** | L7 | Already implemented in `InsightsEngine` (`duplicate_subscription`); benefits directly from §8's identity fix, which is what currently makes it noisy. |

### Tier 3 — Insight and alerting

| Capability | Needs | Behaviour |
|---|---|---|
| **Spending trends** | L8 | Existing SQL aggregates, now reading `net_amount` so refunds are handled once and consistently. |
| **Anomaly alerts** | L8 | Existing 2.5σ detector. Two upgrades: suppress anomalies explained by a known recurring series (an annual insurance premium is not an anomaly), and require an absolute-amount floor so a ₹40 → ₹150 category swing doesn't alert. |
| **Budget insights** | L8, §7.3 | Per-category monthly limits reading the net-spending contract. Projected month-end from the existing burn-rate forecaster. |
| **Personalised summaries** | L7 narrative | Existing grounded pattern: SQL computes every number, the model writes only connective prose, `AnswerRenderer` interpolates deterministic fields. Extended to weekly/monthly digests. |
| **Explain-this-charge** | L3 evidence | Tap any amount → see the source message with the extracted spans highlighted, the parser that produced it, and its confidence. This is the user-facing payoff of the trust boundary, and it is the strongest possible answer to "why should I believe this app". |

---

## 10. Confidence, thresholds, and fallbacks

The existing threshold set is sound and stays. New values are proposed at
conservative defaults and all live in `AppConstants` behind a `feature_flags`
table so they can be tuned without a rebuild.

| Decision | Threshold | Fallback when not met |
|---|---|---|
| Silent auto-label | ≥ 0.90 (existing, adaptive per category) | Ask, then review |
| Ask eligible | ≥ 0.60 + (amount ≥ ₹500 or merchant seen ≥ 3×), budget 2/day (existing) | Review queue |
| Merchant auto-link | ≥ 0.92 cosine (existing) | Review, alias stored as `similarity` |
| Merchant cluster suggestion | ≥ 0.85 cosine (new) | Not suggested |
| LLM span verification | **binary** — verbatim match or refuse | Message → quarantine, never a transaction |
| LLM category suggestion | ≤ 0.70 cap (new) | Falls through to seed map |
| Refund auto-link | ≥ 0.90 (new) | Ranked review card |
| Auth → settle link | ref match, or ≥ 0.85 on auth key (new) | Both rows remain independent |
| Expected → debit fulfilment | ≥ 0.85 (new) | Event stays `expected`, may become `missed` |
| Anomaly alert | 2.5σ over ≥ 8 periods (existing) + absolute floor ₹500 (new) + not explained by a recurring series (new) | No alert |

**Fallback discipline.** Every layer degrades to the layer above it, and the
bottom of every ladder is "show the user, don't guess":

- No model files → `Embedder` and `LlmRuntime` already return typed unavailable
  results and deterministic paths continue. Nothing in this design changes that.
- LLM present but unverifiable output → quarantine, not a transaction.
- Classifier absent → seed map → `other` at 0.3 → review.
- Identity unresolved → new counterparty, `unknown` kind, no merchant row, no
  category guess.
- Link unresolved → separate transactions, both visible. Never merge on doubt.

---

## 11. Privacy, consent, and Play policy

### 11.1 Google Play SMS permissions

Play restricts the SMS permission group to default SMS/Phone/Assistant handlers,
**with a documented exception list**. PaisaTrack falls under a named exception:

> **SMS-based money management** — For example, apps that track and manage
> budget — `READ_SMS`, `RECEIVE_MMS`, `RECEIVE_SMS`, `RECEIVE_WAP_PUSH`

Consequences for the release lane (feeds T-094 and T-125):

- The exception covers exactly those four permissions. `SEND_SMS` and
  `WRITE_SMS` are **not** included — the manifest must not declare them, and no
  dependency may pull them in transitively. Verify with a merged-manifest check
  in CI.
- A **Permissions Declaration Form** is mandatory, and grants are case-by-case.
  The declaration must match reality precisely, and re-submission is required
  whenever the usage changes.
- Core functionality must be *prominently documented and promoted in the store
  listing* — budget tracking from SMS has to be the headline, not a feature
  bullet. Without the permission the app must be visibly degraded, which
  T-113's continue-without-SMS path already demonstrates honestly.
- Play's **Spyware policy** singles this case out: budgeting apps may not
  exfiltrate or share non-financial or personal SMS history. PaisaTrack's
  no-network-inference stance (ADR 0002) over-satisfies this, and the
  `INTERNET`-for-model-download-only justification should be stated verbatim in
  the declaration.
- The L0 admission redesign (§5) reads more messages before rejecting. This does
  **not** change the permission surface — the same permission already grants
  access — but the declaration and privacy policy must describe shape-based
  triage accurately rather than implying a fixed bank allowlist.
- Fallback if a declaration is refused: the sideload/portfolio distribution path
  already contemplated in T-094. Design nothing that assumes Play availability.

### 11.2 Consent and disclosure

- **Prominent disclosure before the runtime prompt**, in-app, in the user's own
  words: what is read, that it stays on the device, what happens if they decline.
  This is a Play User Data requirement, not just good manners.
- **Granular, revocable capture control**: per-sender and per-category-of-message
  opt-outs, and a global pause. Revocation must stop capture immediately and
  visibly.
- **Separate consent for the optional model download** — already implemented, and
  the right pattern to extend.
- **Quarantine is disclosed**: the "Messages we couldn't read" screen must state
  that the message body is stored locally, encrypted, for up to 30 days.

### 11.3 Data minimisation

| Data | Rule |
|---|---|
| Raw SMS bodies | 30-day retention (existing), extended to quarantined messages |
| Evidence spans | Offsets + verbatim substring only; expire with their `raw_sms` row, after which the transaction keeps values and loses the span (evidence view degrades gracefully to "source expired") |
| Account identifiers | Masked at parse time (`xx1234`) — existing `FieldNormalizer` behaviour |
| Person counterparties | Phone numbers hashed into the identity key, never stored raw |
| Model prompts | Never leave the device; existing ADR 0009 boundary |
| Diagnostics / counters | Content-free reason codes only, durable, never bodies — the T-129 contract |
| Backups | Passphrase-encrypted; exclude raw and quarantined SMS by default (T-127) |

---

## 12. Edge cases

Grouped by layer, with the required behaviour. These are the acceptance surface
for the tickets in §17.

**Message and format**

1. Multipart SMS split mid-amount → reassemble before admission; never parse a
   fragment.
2. Amount with no decimal and no separator (`Rs 250000`) → parse; the existing
   balance/limit exclusion already guards the common false positive.
3. Lakh/crore words (`Rs 2.5 Lakh`) → locale pack multiplier; reject if
   ambiguous.
4. Non-INR amounts (`USD 42.00 spent`) → capture currency; do **not** convert;
   exclude from INR totals with a visible "foreign currency" marker. Silent 1:1
   treatment would be a serious error.
5. Devanagari or transliterated bodies → admission on shape tokens, which are
   Latin even in Hindi templates; extraction falls to grammar/LLM span;
   quarantine on failure.
6. Two amounts, one being available balance → existing balance-range exclusion;
   extend to credit limit, reward points, and "min due".
7. Message containing both a debit and its resulting balance and a promotional
   tail → parse the debit, ignore the tail.
8. Bank marketing that quotes a real past transaction → `promo` kind wins over
   settled verb only when no account token is present (existing `SmsFilter`
   logic, retained).

**Amount and direction**

9. Refund message phrased as a credit to the *card* ("credited to your card
   ending 4412") → credit to a liability source; must not read as income.
10. Credit-card spend is a debit from the card and increases what you owe; card
   bill payment is a transfer, not a spend (§7.4).
11. Interest credited / cashback → `credit`, category `Income`/`Rewards`,
   excluded from "spending reduced" unless linked as a refund.
12. Zero or negative parsed amount → hard refuse; `FieldNormalizer.parseAmount`
   already throws.
13. Amount changes between authorization and settlement (tips, FX) → link on
   `auth` key with ±2% tolerance; settlement amount wins; the auth row becomes
   `superseded`.

**Timing and duplication**

14. Bank and UPI-app alerts arriving 3 minutes apart → existing echo dedup.
15. The same alert re-delivered by the carrier hours later → same `smsId` →
   existing primary-key idempotency.
16. Two genuinely identical payments to the same merchant seconds apart (split
   bill, retry) → must **not** be deduped when ref ids differ. Ref-id
   disagreement is a positive signal of distinctness and should veto the echo
   rule.
17. Auth on the 1st, settlement on the 4th → `auth` key link; only one appears
   in totals.
18. History import replaying messages already ingested live → existing
   idempotent re-import.
19. SMS received while the process is dead → existing open/resume catch-up.
20. Device clock skew or a message whose in-body date differs from receipt time
   → prefer the in-body date; if it is more than 7 days from receipt, keep
   receipt time and flag for review.

**Lifecycle**

21. Debit followed by auto-reversal 20 minutes later (failed UPI) → `reverses`
   link; net zero; both visible.
22. Pending auth that never settles (hotel hold released) → `expired` after the
   channel's window; excluded from totals.
23. Refund arriving after the budget month closed → reduces the *original*
   month per the net-spending contract, and the current month's view explains
   the retroactive change rather than silently restating history.
24. Chargeback → same as reversal, different `link_type` for display.

**Identity**

25. A person whose VPA changes PSP (`9876543210@ybl` → `@paytm`) → same
   phone-derived core, same counterparty.
26. A merchant with a dynamic QR per store → aggregator prefix detection
   collapses them; if it fails, the nightly cluster suggestion catches it.
27. A merchant name that is a substring of another (`AMAZON` / `AMAZON PAY
   LATER`) → exact structured key, no substring matching (§7.2).
28. A user renaming a merchant → label layer only; `merchant_raw` untouched
   (existing guarantee).

**Failure and degradation**

29. Model file deleted mid-session → typed unavailable, deterministic path
   continues (existing).
30. Parser upgrade shipped → quarantined and unparsed messages retried at the
   new `retry_version` (T-129 contract), and previously-parsed rows are **not**
   silently rewritten; changes surface as review suggestions.
31. Database migration failure → existing recovery path; must not route to
   key-loss copy (T-122).
32. A user correction that contradicts a high-confidence auto-label →
   correction always wins, writes feedback, and feeds the adaptive threshold,
   raising that category's bar (existing mechanism).

---

## 13. Evaluation

No telemetry exists and none should. Every metric below is computed either from
in-repo sanitized fixtures (CI) or on-device against the user's own data,
surfaced in the developer diagnostics screen and exportable only by explicit
user action.

### 13.1 Golden corpus

Extend `test/fixtures/sms/` from its current shape (per-bank `.txt` +
`.expected.json`) with three additions:

- **Negative fixtures promoted to positive**: the existing
  `axisbk_bill_due_reminder`, `axisbk_txn_declined_international_disabled`, and
  `axisbk_statement_generated` fixtures gain expected `message_kind` and
  lifecycle outputs instead of asserting rejection.
- **Link fixtures**: ordered message *sequences* with an expected event graph —
  auth→settle, debit→reversal, expense→refund, reminder→fulfilment, bank+wallet
  echo. This is a new fixture shape and the only way to test L5/L6 honestly.
- **Adversarial fixtures**: hallucination bait for the span verifier — messages
  where a plausible-but-absent amount is the tempting answer.

Provenance rules from ADR 0005 apply unchanged: every fixture is `public` or
sanitized `device`, and raw messages are never committed.

### 13.2 Metrics and targets

**Extraction (per-field, on the golden corpus)**

| Metric | Target | Rationale |
|---|---|---|
| Amount precision | **1.000** | Any amount error is a P0. This is the metric the product's credibility rests on. |
| Amount recall, allowlisted senders | ≥ 0.97 | |
| Amount recall, all admitted senders | ≥ 0.85 | Grammar + verified LLM span |
| Direction precision | ≥ 0.999 | A flipped sign is worse than a miss |
| Date accuracy (±1 day) | ≥ 0.98 | |
| Span-verification refusal rate on LLM output | tracked, no target | A *rising* rate means the model is drifting; a zero rate means verification isn't running |

**Admission**

| Metric | Target |
|---|---|
| Financial-SMS admission recall (labelled inbox sample) | ≥ 0.95 |
| Non-financial admission rate (OTP/promo/personal) | ≤ 0.02 |
| Quarantine resolution rate after a parser upgrade | ≥ 0.60 |

**Correlation and lifecycle**

| Metric | Target |
|---|---|
| Over-count rate (₹ double-counted ÷ ₹ total) | < 0.5% |
| Dedup precision (wrongly merged distinct payments) | ≥ 0.999 — merging two real payments is the worst dedup failure |
| Auth→settle match rate, card transactions | ≥ 0.85 |
| Refund auto-link precision | ≥ 0.98 |
| Orphan-pending rate after 14 days | < 5% |

**Identity and categorization**

| Metric | Current (observed) | Target |
|---|---|---|
| Merchants per 1,000 transactions | baseline TBD by T-143 (2,467 merchants observed, denominator unrecorded) | ≥ 70% reduction |
| Review inflow per 100 transactions | baseline TBD (6,807 open rows observed) | < 5 |
| Category top-1 accuracy vs confirmed labels | unmeasured | ≥ 0.85 |
| 7-day correction rate on auto-labelled rows | unmeasured | < 0.10 |
| Uncategorized (`other`) share of spend | unmeasured | < 0.10 |

**Commitments**

| Metric | Target |
|---|---|
| Recurring-series precision (user-confirmed ÷ detected) | ≥ 0.90 |
| Known-subscription detection recall | ≥ 0.85 |
| Next-date mean absolute error | ≤ 2 days |
| Reminder deduplication (one obligation → one event) | ≥ 0.95 |

**System** (feeds T-115/T-092)

Cold start < 2 s · 10,000-message import < 60 s · steady-state PSS < 250 MB with
the model unloaded · no measurable battery regression from nightly work.

### 13.3 Shadow evaluation

Because there is no telemetry, correctness on *real* data can only be measured on
a developer's own device. Build a **shadow mode**: run the new pipeline alongside
the current one, write results to a shadow table, and report the diff (records
gained, records lost, amount deltas, category disagreements) in the dev screen.
Ship nothing that loses a previously-correct transaction. This is the safety net
that makes the L0–L6 rework tractable at all.

---

## 14. Offline behaviour

The app is already offline-complete; this section exists to keep it that way.

- Parsing, identity, categorization, recurrence, analytics, and the assistant
  have **no** network dependency and must never acquire one.
- The single permitted network call is the pinned, hash-verified model download.
  A failed or absent download is a first-class state, not an error.
- Nightly work (`NightlyJob`) is checkpointed and resumable; it must remain
  correct when the device is offline, sleeping, or the app is killed mid-run.
- Every new table in §6 is populated exclusively by on-device computation.
- Backup/restore is file-based through the system document picker — no cloud
  account, no sync service, no server-side reconciliation. Import is idempotent.
- The design adds no server-side model updates. Improvements to templates,
  locale packs, and seed maps ship as **bundled assets in an app update**, which
  keeps the update path auditable and the runtime offline.

---

## 15. Model options

| Role | Recommendation | Alternatives considered |
|---|---|---|
| Text embedding (merchant identity) | Keep the current on-device embedder (ADR 0007) | A char-ngram hashing + SVD embedding as a zero-dependency fallback is worth keeping as the `NoopEmbedder` replacement, so identity degrades rather than disappears when no model is installed |
| Category classifier | Keep the serializable softmax in `model_meta`, upgrade features (§8.3) and add merchant-memory prior | Gradient boosting: better accuracy, materially worse on-device size and training complexity, not justified. A per-user online logistic update is the cheap win. |
| Span location + descriptive inference | Keep Qwen3-0.6B mixed-INT4 via LiteRT-LM (ADR 0009), **retasked** from extractor to locator | Gemma 3 270M is worth benchmarking specifically against the 421–533 MB PSS problem T-115 is chasing; span location is a much easier task than structured extraction, so a smaller model may suffice. Anything requiring a server is out (ADR 0002). |
| Message-kind classification (L1) | **No model.** Deterministic cue-phrase classifier with a locale pack | An ML classifier here would trade total explainability for marginal recall on a task that is genuinely lexical |

Retasking the LLM from extractor to locator also shortens its output
dramatically (quoted spans, not a full record), which reduces latency, reduces
the chance of schema violation, and makes the 2048-token context comfortable.

---

## 16. Rollout

There is no server, no remote config, and no cohort assignment. "Rollout" means
staged local flags plus honest verification.

**Stage 0 — Flags.** Move `AppConstants` behavioural thresholds into a
`feature_flags` table with `AppConstants` as the seed defaults, so shadow mode
and per-layer enablement are toggleable in the dev screen without a rebuild.

**Stage 1 — Shadow.** New pipeline computes, old pipeline decides. Diff reported.
Exit criterion: zero regressions on the golden corpus, and on the developer's own
inbox no lost transaction and no amount delta.

**Stage 2 — Trust boundary live.** Span verification enforced. `LlmExtractor` is
removed from `ParserCascade` in the same change that adds `LlmFieldLocator`, so
there is never a build in which an unverified model amount can be written.

**Stage 3 — Lifecycle and links.** `lifecycle_state` populated; pending/failed
surfaces enabled; refund linking suggested but manual-confirm-only for one
release before auto-linking above 0.90 is turned on.

**Stage 4 — Identity.** Structured keys applied to *new* transactions first, then
a previewed, reversible backfill using the existing label-merge machinery.
Never a silent history rewrite.

**Stage 5 — Commitments and insight.** Expected events, calendar, budgets.

**Cohort.** Dogfood on the developer's own inbox through stages 1–3 (this is the
only realistic large-corpus test available), then a small invited cohort with a
structured on-device feedback export before any public listing.

**Rollback.** Every stage is a flag flip plus, where schema changed, an additive
migration that leaves the previous read path intact. No stage may make a v7
database unreadable.

---

## 17. Phased implementation

Fourteen tickets, `T-131`–`T-144`, added to `TASKS.md` in board format. Existing
board items are unchanged; several become cheaper because their prerequisites
land here. Relationships to current work:

- **T-100** (refunds) is unblocked by T-134/T-135 and should be closed by them.
- **T-101** (recurring calendar) is unblocked by T-132 and T-138.
- **T-098** (budgets) consumes the net-spending contract T-135 defines.
- **T-117 / T-123** (queue and label scale) are structurally reduced by T-136/T-137;
  their paging work remains necessary but on a much smaller queue.
- **T-108 / T-129** (coverage and diagnostics) are prerequisites for T-133 and
  are strengthened by its quarantine store.
- **T-126** (calendar and spending semantics) must land before or with T-135;
  both define "what counts as spending" and there can only be one answer.
- **T-130** (integer paise) — every new monetary column here is already paise, so
  T-130's migration shrinks to the legacy `transactions.amount` column.

### Phase A — Foundation (blocks everything)

| Ticket | Priority | Summary |
|---|---|---|
| T-131 | P0 | Numeric trust boundary: `FieldEvidence`, `SpanVerifier`, `LlmFieldLocator` replacing `LlmExtractor` |
| T-132 | P0 | Message-kind classifier and `lifecycle_state` split (schema v8) |
| T-143 | P1 | Golden corpus extension, shadow mode, and the on-device metrics surface |

T-143 is listed in Phase A deliberately: without shadow mode and link fixtures,
Phases B and C cannot be verified safely.

### Phase B — Truth layer

| Ticket | Priority | Summary |
|---|---|---|
| T-133 | P1 | Admission redesign: shape-based triage, quarantine store, retry-on-upgrade |
| T-134 | P1 | Financial events and the transaction link graph |
| T-135 | P1 | Refunds, reversals, cash, transfers, and the single net-spending contract |
| T-136 | P1 | Structured counterparty identity and the person/merchant split |
| T-137 | P2 | Nightly merchant cluster suggestions and bulk review resolution |

### Phase C — Commitments

| Ticket | Priority | Summary |
|---|---|---|
| T-138 | P2 | Expected events from reminder and mandate messages, plus fulfilment matching |
| T-139 | P2 | Subscription and EMI classification, price-change and missed-payment alerts |

### Phase D — Insight and release

| Ticket | Priority | Summary |
|---|---|---|
| T-140 | P2 | Categorization ladder: merchant memory, feature upgrade, capped LLM suggestion |
| T-141 | P3 | Anomaly quality: recurring-series suppression and an absolute-amount floor |
| T-142 | P3 | Explain-this-charge evidence view |
| T-144 | P1 | Play SMS declaration, consent disclosure, and capture controls |

T-144 is P1 despite sitting in the last phase: the declaration text must describe
the admission behaviour T-133 ships, so it cannot be written earlier, but it
gates distribution (T-094) and should not be discovered late.

### Suggested order

```
T-131 → T-143 → T-132 → T-133 → T-134 → T-135 → T-136 → T-137
      → T-138 → T-139 → T-140 → T-141 → T-142 → T-144
```

T-131 first because it is small, self-contained, and closes a correctness hole
that is live in production code today.

---

## 18. Open questions

1. **Pending in the headline total.** Excluded by default here. Users of card-heavy
   accounts may find the headline lags reality by days. Worth a user-level setting
   rather than a design decision made once.
2. **Credit-card bill exclusion.** Correct, and the most confusing exclusion in the
   app. Needs UX work, not just logic.
3. **Quarantine retention.** 30 days matches `raw_sms`, but a template written on
   day 40 cannot retry a message purged on day 30. A longer, content-free
   *fingerprint* retention (sender + shape signature, no body) would let the app
   at least report "we now support 14 messages we previously missed — re-import?".
4. **Foreign currency.** Captured but not converted. Any conversion needs rates,
   which needs a network call, which ADR 0002 forbids. Manual per-transaction
   rate entry is the only offline-honest answer.
5. **`transactions.amount` as REAL.** Every new column here is paise, but the
   legacy column stays until T-130. Mixed-representation arithmetic during the
   transition is a real bug risk and needs a single conversion helper.

## 19. References

- `docs/architecture.md`, `docs/schema.md`, `docs/privacy.md`
- ADR 0002 (no cloud services), 0003 (dedup and counterparty), 0005 (fixture
  provenance and parse trust), 0007 (on-device embedding), 0009 (LiteRT-LM and
  Qwen3)
- [Use of SMS or Call Log permission groups — Play Console Help](https://support.google.com/googleplay/android-developer/answer/10208820)
- [Declare permissions for your app — Play Console Help](https://support.google.com/googleplay/android-developer/answer/9214102)
- [Permissions and APIs that Access Sensitive Information — Play Console Help](https://support.google.com/googleplay/android-developer/answer/16558241)
