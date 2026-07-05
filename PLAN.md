# PaisaTrack — SMS-Based Intelligent Expense Tracker
## Complete Project Plan & Build Specification

> **Purpose of this document:** This is the master plan for building an Android-first, privacy-first, on-device intelligent expense tracker that reads bank/UPI SMS messages, structures them into transactions, enriches them with ML, learns from user feedback, and produces insights. It is written to be handed to an AI coding agent (Codex/Claude Code) as the project brief, and to serve as the developer's own reference. Follow phases in order. Do not skip Phase 0.

---

## 1. Product Vision

**One-liner:** A personal finance app that turns transactional SMS into an intelligent, self-improving money dashboard — where all parsing and ML happens on-device, and no raw financial data ever leaves the phone.

**Core principles (non-negotiable, enforce in every PR):**
1. **Local-first:** Raw SMS text and transaction records never leave the device. Cloud LLM calls (optional, Phase 4+) receive only anonymized snippets or aggregate JSON.
2. **Confidence-driven autonomy:** Every ML decision carries a confidence score. High confidence → act silently. Medium → ask the user smartly. Low → defer to batch review. Never confidently wrong.
3. **Every user answer is used forever:** One correction creates a rule + a training example + an alias entry. The app must never ask the same question twice.
4. **Low interruption budget:** Max 2 "ask now" notifications per day. Everything else batches into a weekly review.
5. **The normalized transaction record is the contract:** All downstream modules consume the same schema (§6.2). Parser internals can change; the record cannot (without a migration).

**Explicit non-goals (v1):**
- No iOS version (iOS does not allow SMS access).
- No bank account linking / account aggregator APIs.
- No multi-user, no social features, no cloud sync (encrypted export/import only).
- No investment tracking, no loan offers, no monetization hooks.

---

## 2. Tech Stack

| Concern | Choice | Rationale |
|---|---|---|
| App framework | **Flutter (Dart), stable channel** | Cross-skill value; single codebase for future expansion; team familiarity goal |
| Native layer | **Kotlin** (Android module) | SMS BroadcastReceiver/ContentObserver MUST be native; exposed via platform channel |
| Local DB | **SQLite via `drift`** (Dart) + **SQLCipher** | Type-safe queries, migrations, encryption at rest |
| State management | **Riverpod** | Testable, compile-safe DI + state |
| On-device ML (Phase 4) | **MediaPipe LLM Inference API** (Gemma-2B class) or `llama.cpp` via FFI | Structured extraction fallback for unknown SMS formats |
| Embeddings (Phase 3) | Small sentence-embedding model via **TFLite / MediaPipe Text Embedder** | Merchant entity resolution |
| Classic ML (Phase 3) | Pure Dart implementations (logistic regression, statistics) — no heavy deps | Tiny models, trivial math, full control |
| Cloud LLM fallback (Phase 4, optional) | Anthropic API (claude-haiku class) behind a feature flag | Last-resort parsing + monthly narrative generation; anonymized input only |
| Charts | `fl_chart` | Dashboard visualizations |
| Notifications | `flutter_local_notifications` + Android notification actions | Tappable 3-guess ask flow |
| Background work | **WorkManager** (native, bridged) | Nightly retraining, recurring-series scan, SMS backfill |
| Testing | `flutter_test`, `mocktail`, `integration_test`, JUnit for Kotlin | See §10 |
| CI | GitHub Actions | Lint + test on PR; debug APK artifact on main |

**Minimum SDK:** Android 8.0 (API 26). **Target:** latest stable.

---

## 3. Repository & Folder Structure

```
paisatrack/
├── README.md
├── PLAN.md                          # this document
├── docs/
│   ├── architecture.md              # layer diagram + data-flow description
│   ├── sms-templates.md             # catalog of known bank SMS formats (living doc)
│   ├── schema.md                    # DB schema + migration log
│   ├── decisions/                   # ADRs: 0001-flutter-vs-native.md, etc.
│   └── privacy.md                   # data lifecycle, what leaves device (nothing), threat model
├── android/
│   └── app/src/main/kotlin/com/paisatrack/
│       ├── sms/
│       │   ├── SmsBroadcastReceiver.kt    # incoming SMS (RECEIVE_SMS)
│       │   ├── SmsInboxReader.kt          # historical backfill (READ_SMS, content://sms)
│       │   ├── SmsFilter.kt               # sender-ID allowlist, OTP/promo rejection
│       │   └── SmsChannelHandler.kt       # MethodChannel/EventChannel bridge to Flutter
│       ├── work/
│       │   └── NightlyJobsWorker.kt       # WorkManager: triggers Dart background isolate
│       └── notifications/
│           └── AskNotificationBuilder.kt  # notification with 3 action buttons + free-text remote input
├── lib/
│   ├── main.dart
│   ├── app.dart                     # MaterialApp, routing, theming
│   ├── core/
│   │   ├── constants.dart           # thresholds, budgets, feature flags
│   │   ├── result.dart              # Result<T, E> type used everywhere
│   │   ├── logging.dart
│   │   └── crypto/                  # SQLCipher key management via Android Keystore
│   ├── data/
│   │   ├── db/
│   │   │   ├── database.dart        # drift database definition
│   │   │   ├── tables/              # one file per table (see §6)
│   │   │   └── migrations/
│   │   ├── repositories/
│   │   │   ├── transaction_repository.dart
│   │   │   ├── merchant_repository.dart
│   │   │   ├── rule_repository.dart
│   │   │   ├── recurring_repository.dart
│   │   │   └── feedback_repository.dart
│   │   └── models/                  # freezed data classes (TransactionRecord, Merchant, ...)
│   ├── capture/
│   │   ├── sms_channel.dart         # receives SMS events from Kotlin
│   │   ├── parser_cascade.dart      # orchestrates template → local LLM → cloud (flagged)
│   │   ├── template_engine/
│   │   │   ├── template_registry.dart     # loads templates from assets/templates/*.json
│   │   │   ├── template_matcher.dart      # sender-ID + regex matching
│   │   │   └── field_normalizer.dart      # amounts, dates, account hints → canonical forms
│   │   ├── llm_extractor.dart       # on-device LLM structured extraction (Phase 4)
│   │   ├── cloud_extractor.dart     # anonymize → cloud → parse JSON (Phase 4, flagged)
│   │   └── anonymizer.dart          # masks amounts/accounts/names before any cloud call
│   ├── intelligence/
│   │   ├── pipeline.dart            # runs enrichers in order, assembles confidence trail
│   │   ├── enrichers/
│   │   │   ├── merchant_resolver.dart     # alias table → embedding similarity
│   │   │   ├── categorizer.dart           # rules → local classifier → seed map / LLM
│   │   │   ├── recurring_detector.dart    # periodicity mining (batch job)
│   │   │   └── anomaly_detector.dart      # rolling per-category/merchant baselines
│   │   ├── models/
│   │   │   ├── classifier.dart            # logistic regression over features (pure Dart)
│   │   │   ├── embedder.dart              # TFLite text-embedding wrapper
│   │   │   └── trainer.dart               # nightly retrain from feedback table
│   │   ├── decision_policy.dart     # confidence × value → silent / ask-now / batch
│   │   ├── forecaster.dart          # burn-rate curve vs historical month curves
│   │   └── insights_engine.dart     # SQL aggregates → insight objects (+ optional LLM narrative)
│   ├── experience/
│   │   ├── screens/
│   │   │   ├── onboarding/          # permission flow, backfill progress, bank selection
│   │   │   ├── dashboard/           # summary cards, category donut, trend line, anomaly chips
│   │   │   ├── transactions/        # list, filters, detail + edit (edits = feedback)
│   │   │   ├── review/              # weekly batch review queue (swipe to confirm/correct)
│   │   │   ├── recurring/           # subscriptions/EMIs, next dates, price-creep flags
│   │   │   ├── insights/            # monthly narrative, savings suggestions
│   │   │   └── settings/            # flags, export/import, ask-budget, category manager
│   │   ├── widgets/                 # shared components
│   │   └── notifications/
│   │       └── ask_flow.dart        # builds 3-guess payloads, handles action responses
│   └── background/
│       └── nightly_jobs.dart        # retrain, recurring scan, baseline refresh, insight precompute
├── assets/
│   ├── templates/                   # JSON template registry per sender (hdfc.json, sbi.json...)
│   └── seed/
│       ├── category_seed.json       # merchant → category seed map
│       └── categories.json          # category taxonomy (id, name, icon, parent)
├── test/                            # unit tests mirror lib/ structure
│   ├── capture/parser_cascade_test.dart
│   ├── capture/template_engine/     # fixture-driven: real (sanitized) SMS in test/fixtures/sms/
│   ├── intelligence/...
│   └── fixtures/
│       └── sms/                     # 100+ sanitized real SMS samples, per bank, expected JSON alongside
├── integration_test/
│   ├── ingest_flow_test.dart        # SMS in → transaction visible on dashboard
│   └── feedback_loop_test.dart      # correction → rule created → next txn auto-labeled
└── .github/workflows/ci.yml
```

**Conventions for the coding agent:**
- Every module in `lib/` gets a matching test file before it is considered done.
- All enrichers implement `abstract class Enricher { Future<EnrichmentResult> enrich(TransactionRecord txn); }` where `EnrichmentResult` = `{field, value, confidence, source}`.
- No enricher writes to the DB directly; only `pipeline.dart` commits, atomically, with the full confidence trail.
- Feature flags in `constants.dart`: `enableLocalLlm`, `enableCloudFallback`, `enableNarrativeInsights` — all default **false** until their phase.
- Never log raw SMS bodies at info level. Debug-only, stripped in release builds.

---

## 4. Feature Inventory (complete list, tagged by phase)

### Capture
- [P1] Runtime permission flow for RECEIVE_SMS / READ_SMS with clear explanation screen
- [P1] Live SMS listener (native → Dart bridge)
- [P1] Historical inbox backfill (last 12 months) with progress UI
- [P1] Sender-ID allowlist + junk filter (OTPs, promos, delivery notifications rejected)
- [P1] Template-based parser for top Indian banks/wallets: HDFC, SBI, ICICI, Axis, Kotak, Paytm, PhonePe, GPay-linked bank alerts, Amazon Pay
- [P2] Manual transaction entry (cash expenses) + quick-add widget
- [P4] On-device LLM extraction fallback for unmatched formats
- [P4] Anonymized cloud extraction fallback (feature-flagged, off by default)
- [P2] Duplicate suppression (same ref_id / same amount+time from two SMS, e.g., bank + wallet both notify)

### Storage & Data
- [P1] Encrypted SQLite (SQLCipher, key in Android Keystore)
- [P1] Full schema (§6) with drift migrations
- [P1] Raw SMS retention window (30 days) then automatic purge; transactions kept forever
- [P2] Encrypted export (JSON + passphrase) and import — the only "sync"
- [P3] Feedback table capturing every correction with before/after and context

### Intelligence
- [P1] Field normalization (amount, direction, channel, account hint, balance, ref)
- [P2] Merchant resolution v1: exact alias table + learned aliases
- [P3] Merchant resolution v2: embedding similarity with auto-alias promotion (≥0.92) and review band (0.75–0.92)
- [P2] Categorization v1: seed map + user rules
- [P3] Categorization v2: local classifier trained nightly on feedback (features: merchant embedding, amount band, hour, day-of-week, channel)
- [P3] Recurring detection: merchant×amount clustering + periodicity test; series records with next_expected_date
- [P3] Anomaly detection: rolling mean/σ per category-week and merchant-month; 2.5σ flags
- [P2] Decision policy v1: static thresholds (silent ≥0.9; ask 0.6–0.9 if amount ≥ ₹500 or merchant frequency ≥3; else batch)
- [P3] Decision policy v2: adaptive per-category thresholds (rise on repeated corrections)
- [P3] Burn-rate forecaster: cumulative day-of-month curve vs trailing-3-month curves
- [P4] Insight narratives via LLM over aggregate JSON only (flagged)
- [P3] Deterministic insights (no LLM): duplicate subscriptions, fee/penalty totals, price creep, category deltas, missed autopay

### Experience
- [P1] Onboarding: privacy explainer → permissions → bank detection from inbox → backfill
- [P1] Dashboard: month summary (in/out/net), category breakdown, recent transactions, spend trend
- [P1] Transaction list with search/filter; detail screen with editable category/description (edits feed feedback)
- [P2] Ask-now notification: 3 tappable guesses + free-text reply; daily budget of 2
- [P2] Weekly review screen: swipe-to-confirm queue of uncertain transactions
- [P3] Recurring screen: subscriptions/EMIs, upcoming renewals, price-creep and missed-payment alerts
- [P3] Insights screen: monthly report, savings suggestions, anomaly explanations
- [P2] Category manager: add/rename/merge categories (merges retro-apply)
- [P2] Settings: ask budget, quiet hours, export/import, feature flags, data purge ("delete everything")
- [P5] Home-screen widget: month net + last transaction
- [P5] App lock (biometric)

### Learning Loop
- [P3] Correction → rule + training example + alias, in one write
- [P3] Nightly retrain job (WorkManager, charging + idle constraints)
- [P3] Confidence trail stored per transaction (per-enricher source + score) for debugging
- [P3] Model metrics screen (hidden dev screen): classifier accuracy on last 100 feedback items, ask-rate, correction-rate per category

---

## 5. Category Taxonomy (seed)

Two levels. Users can add/rename; these ship as defaults:

`Food & Dining` (restaurants, delivery, cafes) · `Groceries` · `Transport` (fuel, cab, metro, FASTag) · `Shopping` (online, offline, electronics, clothing) · `Bills & Utilities` (electricity, mobile/DTH, broadband, gas) · `Subscriptions` (OTT, music, cloud, apps) · `Rent & Housing` · `EMI & Loans` · `Health` (pharmacy, doctor, insurance) · `Education` · `Entertainment` · `Travel` · `Transfers` (P2P sent/received, self-transfer) · `Income` (salary, refunds, cashback, interest) · `Fees & Charges` (bank fees, late fees, GST on fees) · `Cash Withdrawal` · `Investments` · `Other`

Rules: `Transfers` and `Cash Withdrawal` are excluded from "spending" aggregates by default (toggleable). `Fees & Charges` is always surfaced in insights.

---

## 6. Data Model

### 6.1 Tables

**transactions**
```
id TEXT PK (uuid)
ts INTEGER (epoch ms)             -- transaction time from SMS, not receipt time
amount REAL                       -- always positive
direction TEXT                    -- 'debit' | 'credit'
channel TEXT                      -- 'upi' | 'card' | 'netbanking' | 'atm' | 'wallet' | 'cash' | 'unknown'
account_hint TEXT                 -- 'xx4521'
merchant_raw TEXT
merchant_id TEXT FK -> merchants  -- nullable until resolved
category_id TEXT FK -> categories
description TEXT                  -- user or auto description
balance_after REAL NULL
ref_id TEXT NULL                  -- UPI ref / txn id, used for dedup
parse_source TEXT                 -- 'template' | 'local_llm' | 'cloud' | 'manual'
sms_id TEXT NULL FK -> raw_sms    -- null after purge
confidence_json TEXT              -- {"merchant":{"v":...,"c":0.94,"src":"alias"},"category":{...}}
status TEXT                       -- 'auto' | 'confirmed' | 'needs_review' | 'asked'
is_deleted INTEGER DEFAULT 0
created_at, updated_at
INDEXES: (ts), (merchant_id), (category_id), (ref_id), (status)
```

**raw_sms** — `id, sender, body, received_at, processed INTEGER, purge_after` (30-day TTL job)

**merchants** — `id, canonical_name, category_hint TEXT NULL, embedding BLOB NULL, txn_count, first_seen, last_seen`

**merchant_aliases** — `alias TEXT PK, merchant_id FK, source ('seed'|'learned'|'user'), confidence`

**categories** — `id, name, parent_id NULL, icon, is_spending INTEGER, sort_order, is_user_created`

**rules** — user-taught hard mappings:
```
id, match_type ('merchant'|'counterparty'|'regex'|'amount_merchant'),
match_value TEXT, set_category_id NULL, set_description NULL,
created_from_txn_id, hit_count, created_at
```
Rules always win over the classifier. Rules are visible/editable in settings.

**recurring_series** — `id, merchant_id, label, expected_amount REAL, tolerance_pct, period ('weekly'|'monthly'|'quarterly'|'yearly'|'custom_days'), period_days INT, next_expected_date, last_amount, amount_trend ('flat'|'rising'), occurrences INT, status ('active'|'paused'|'ended'), kind ('subscription'|'emi'|'bill'|'income')`

**feedback** — the training data:
```
id, txn_id, field ('category'|'merchant'|'description'),
old_value, new_value, context ('ask_now'|'batch_review'|'detail_edit'|'silent_confirm'),
model_confidence_at_time REAL, created_at
```

**baselines** — `key TEXT PK ('cat:<id>:week' | 'mer:<id>:month'), mean REAL, std REAL, n INT, updated_at`

**model_meta** — `key, value` (classifier weights JSON, version, last_trained_at, per-category thresholds)

**insights** — precomputed: `id, period ('2026-07'), kind, payload_json, dismissed INTEGER`

### 6.2 The Normalized Transaction Record (the contract)

Every parser path must emit exactly:
```json
{
  "amount": 449.00,
  "direction": "debit",
  "channel": "upi",
  "merchant_raw": "AMZN*MKTPLC",
  "counterparty_vpa": null,
  "account_hint": "xx4521",
  "balance_after": 12384.50,
  "ref_id": "615223847712",
  "ts": 1751702400000,
  "parse_source": "template",
  "parse_confidence": 0.97
}
```
Missing fields → null, never guessed. `parse_confidence < 0.6` → transaction created with `status='needs_review'`.

### 6.3 Template format (`assets/templates/hdfc.json`)
```json
{
  "sender_patterns": ["^[A-Z]{2}-HDFCBK$", "^HDFCBK$"],
  "templates": [
    {
      "id": "hdfc_upi_debit_v1",
      "regex": "Rs\\.?\\s?(?<amount>[\\d,]+\\.?\\d*) debited from a/c \\*\\*(?<account>\\d{4}) .* to (?<merchant>.+?) on (?<date>\\d{2}-\\d{2}-\\d{2}).*Ref (?<ref>\\d+)",
      "direction": "debit",
      "channel": "upi",
      "date_format": "dd-MM-yy"
    }
  ]
}
```
Templates are data, not code — adding a bank never requires an app update logic change, only a registry entry + fixtures.

---

## 7. Intelligence Design (implementation-level)

### 7.1 Parser cascade (`parser_cascade.dart`)
```
input: RawSms
1. SmsFilter (native pre-filter already dropped obvious junk; Dart re-checks)
2. TemplateMatcher: find sender registry → try templates in order → on match, normalize fields → confidence 0.95+ (deterministic)
3. [flag] LlmExtractor: prompt on-device model with SMS + JSON schema → validate output (amount parses, direction ∈ enum, ts sane) → model confidence × validation score
4. [flag] CloudExtractor: anonymizer masks digits-runs>4, names after "to/from", VPAs → cloud → same validation
5. No path succeeded → store raw_sms with processed=0, surface in "unparsed" dev list
output: NormalizedRecord | Unparsed
```
Validation is code, not vibes: reject extraction where amount ≤ 0, ts in future, direction missing.

### 7.2 Enrichment pipeline order
`merchant_resolver → categorizer → (async batch: recurring_detector, anomaly_detector)`
Pipeline commits transaction + confidence trail in one DB transaction, then hands to `decision_policy`.

### 7.3 Merchant resolver
1. Exact alias lookup (case/punct-normalized) → confidence 1.0
2. Embedding similarity vs all merchant embeddings (brute force is fine — a user has <2k merchants): ≥0.92 auto-link + write learned alias; 0.75–0.92 link with `needs_review` mark; <0.75 create new merchant (embed and store)

### 7.4 Categorizer ladder
1. **Rules** (user-taught) → confidence 1.0, done
2. **Local classifier** (once trained, `model_meta` has weights): features = merchant embedding (or merchant-id one-hot for top-N) + log-amount-band + hour-bucket + dow + channel; output = softmax over categories; use if top-prob ≥ per-category threshold
3. **Seed map** by merchant → 0.8
4. **[flag] LLM zero-shot** on `{merchant_canonical, amount_band, channel}` (no raw SMS) → capped 0.75
5. Nothing → `Other`, confidence 0.3, guaranteed to enter ask/batch flow

### 7.5 Decision policy
```
c = min(merchant.c, category.c)
if c >= silent_threshold(category)          -> status 'auto'
elif c >= 0.6 and (amount >= 500 or merchant.txn_count >= 3) and ask_budget_left
                                            -> 'asked' + notification (3 guesses = top-3 classifier cats or rule suggestions)
else                                        -> 'needs_review' (weekly batch)
P2P counterparty never seen before          -> always ask once (rule created from answer)
```
Adaptive thresholds (P3): if corrections/auto-labels in a category > 15% over trailing 50, raise that category's silent threshold by 0.03 (cap 0.98); lower by 0.01 per clean 50.

### 7.6 Recurring detector (nightly batch)
Group by merchant_id → sub-cluster by amount (±5%) → compute inter-arrival gaps → periodicity if median gap ∈ known bands and coefficient of variation < 0.25 with ≥3 occurrences → upsert series, set `next_expected_date = last_ts + median_gap`. Flags: `rising` if last 3 amounts monotonically increase; `missed` if today > next_expected_date + grace(20% of period).

### 7.7 Anomaly detector (nightly)
Update Welford running mean/σ per `cat:<id>:week` and `mer:<id>:month`. Flag when current period aggregate > mean + 2.5σ and n ≥ 8 periods. Insight payload includes the top 3 contributing transactions.

### 7.8 Forecaster
Cumulative spend by day-of-month for current month vs. per-day median of trailing 3 months → project month-end = current + median remaining-days spend → insight if projection deviates > 10% from 3-month average.

### 7.9 Nightly job order
`purge expired raw_sms → recurring scan → baselines → retrain classifier (if ≥30 new feedback rows) → recompute thresholds → precompute insights for dashboard`
Constraints: device idle + charging; hard cap 3 minutes, resumable.

---

## 8. Privacy & Security Checklist
- SQLCipher key generated on first run, stored in Android Keystore (StrongBox where available)
- No analytics SDKs. Crash reporting local-only log ring buffer, user-exportable
- Cloud calls (when flagged on): anonymizer unit-tested to strip account numbers, full names after to/from, VPAs, and to bucket amounts; payloads logged in debug for audit
- `Delete everything` in settings wipes DB + key and proves it (recreates empty DB)
- Export encrypted with user passphrase (Argon2id + AES-GCM)
- Play Store: SMS permission requires a declaration — the core functionality IS SMS-based finance tracking, which is an accepted use case; write the declaration in Phase 5. Distribute as APK/sideload during development.

---

## 9. Phased Roadmap

### Phase 0 — Foundation (Week 1)
Repo, CI, Flutter project, drift + SQLCipher wired, schema v1 migrated, Riverpod skeleton, docs/ stubs, fixture harness (`test/fixtures/sms/` format: `<bank>/<case>.txt` + `<case>.expected.json`).
**Exit criteria:** `flutter test` green in CI; encrypted DB creates and migrates; a fixture test runner loads fixtures and asserts parser output (with 0 templates, all fixtures are "unparsed" — the harness itself is what's being proven).

### Phase 1 — Capture MVP (Weeks 2–3)
Kotlin SMS receiver + inbox backfill + filter; platform channel; template engine + registries for your own banks first (collect 30+ real SMS per bank into fixtures, sanitized); normalizer; transactions list UI; basic dashboard; onboarding + permissions.
**Exit criteria:** Fresh install on your phone parses ≥90% of your last 3 months of bank SMS into correct transactions (verified by hand against bank statement); duplicates from paired bank+wallet SMS are suppressed; unparsed messages visible in dev screen.

### Phase 2 — Usable Tracker (Weeks 4–5)
Manual entry; detail edit (writes feedback rows even before ML uses them); category manager; seed-map categorization + rules engine; decision policy v1 with static thresholds; ask-now notification with 3 guesses + free text; weekly review screen; settings; encrypted export/import.
**Exit criteria:** You use it daily; ≤2 asks/day; a correction on a P2P transfer creates a visible rule and the next identical transfer auto-labels; export→wipe→import round-trips losslessly.

### Phase 3 — Intelligence (Weeks 6–9)
Embedder + merchant resolver v2; local classifier + nightly trainer; adaptive thresholds; recurring detector + recurring screen; anomaly baselines; forecaster; deterministic insights + insights screen; model metrics dev screen; WorkManager nightly jobs.
**Exit criteria:** After 2 weeks of feedback, classifier auto-labels ≥80% of new transactions with ≤10% correction rate (metrics screen proves it); at least your real subscriptions/EMIs all appear in recurring with correct next dates; one genuine anomaly and one forecast insight have fired correctly.

### Phase 4 — LLM Layer (Weeks 10–12, feature-flagged)
On-device LLM extractor for unmatched SMS (measure: unparsed rate should drop toward ~0); anonymizer + optional cloud fallback; monthly narrative insight from aggregate JSON.
**Exit criteria:** Unparsed rate < 2% on a fresh bank you never wrote templates for; anonymizer test suite passes adversarial cases; narrative renders from aggregates with zero raw text in the prompt (asserted in tests).

### Phase 5 — Polish & Release (Weeks 13–14)
App lock, home widget, empty states, performance pass (backfill of 10k SMS < 60s), accessibility (TalkBack labels, contrast), Play declaration or sideload distribution page, README with screenshots + architecture writeup (this is the portfolio artifact).
**Exit criteria:** Cold start < 2s; a friend onboards without help; README tells the privacy + on-device-ML story convincingly.

---

## 10. Testing Strategy
- **Fixture-driven parser tests** are the backbone: every real-world SMS variant becomes a fixture the moment it's seen. Regression = re-run all fixtures. Target: 100+ fixtures by Phase 1 end.
- **Unit:** normalizer edge cases (₹ vs Rs vs INR, lakh-comma formats `1,00,000`, dd-MM vs dd/MM dates, credited-vs-debited wording traps, "declined"/"failed" SMS must NOT create transactions), dedup logic, decision policy table-driven tests, recurring detector on synthetic series (monthly, weekly, price-creep, missed), Welford math, anonymizer adversarial cases.
- **Property tests:** classifier trainer never crashes on degenerate feedback (1 class, duplicate rows); alias normalization idempotent.
- **Integration:** SMS event → dashboard row; correction → rule → auto-label; nightly job full run on seeded DB.
- **Kotlin:** filter allowlist/rejection JUnit tests; receiver → channel contract test.
- **Manual QA checklist per release:** permission denial paths, airplane-mode behavior (everything must work offline), notification actions with app killed, DB migration from previous version, dark mode, double-tap on ask buttons.

---

## 11. Milestone Demo Script (how you know it's "complete")
1. Fresh install → onboarding → backfill 12 months → dashboard populated in under a minute.
2. Receive a real UPI payment SMS → transaction appears within seconds, correctly categorized silently.
3. Pay a new unknown person → ask notification with 3 guesses → tap "Rent" → rule visible in settings → pay them again next month → silent, correct.
4. Recurring screen shows all your actual subscriptions with next renewal dates; one shows a price-creep flag.
5. Insights shows: month forecast, a category anomaly with contributing transactions, duplicate-subscription suggestion, quarterly fees total.
6. Metrics dev screen: ≥80% auto-label rate, correction rate trending down week over week.
7. Airplane mode on → everything above still works.
8. Settings → Delete everything → app is factory-empty.

---

## 12. Instructions to the Coding Agent (Codex)
- Work phase by phase; do not begin a phase until the previous phase's exit criteria have tests proving them.
- Every PR: code + tests + updated docs (schema.md on any migration, sms-templates.md on any template).
- Never invent SMS formats — request fixtures from the developer; the developer supplies sanitized real samples.
- Keep the normalized record schema (§6.2) frozen; propose an ADR in `docs/decisions/` for any change.
- Prefer boring, dependency-light solutions; every new package needs one-line justification in the PR description.
- All thresholds/budgets live in `constants.dart`, never inline.
- Raw SMS text must never appear in: logs (release), cloud payloads, exports without encryption, or LLM prompts (only anonymized text in the flagged extractor path).