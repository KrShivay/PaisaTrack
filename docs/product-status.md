# Product Status

Status date: 2026-08-01
Code baseline: current `main` worktree, including T-126 calendar/eligibility
semantics and T-156a dialog consolidation

This is the source of truth for current product state. Normative technical
contracts live in the linked `docs/` files, future outcomes live in `PLAN.md`,
and unfinished delivery work lives only in `TASKS.md`.

## Outcome summary

PaisaTrack is a functional Android-first, local-first finance tracker built
around transactional SMS. Its capture, encrypted storage, correction,
categorization, recurring detection, deterministic analytics, grounded
assistant, backup, and most Bloom UI paths are implemented and covered by a
large host-side test suite.

The completed P0 fixes (T-121–T-126) removed fabricated dashboard guidance,
permission/key-loss recovery failures, optimistic Sort completion, incomplete
local erasure/key persistence, and unsafe release signing defaults. It is not
production-ready: capture retry diagnostics,
backup bounds, accessibility/device acceptance, and release/device evidence
remain open.

## Product-value review snapshot

The 2026-08 review is documented in
[`docs/product-value-review-2026-08.md`](product-value-review-2026-08.md), with
the synthetic local-only corpus at
`test/fixtures/product_review/corpus.json` and the release cadence at
[`docs/product-quality-review.md`](product-quality-review.md).

The evidence-backed priority is trust first: full-history discoverability,
truthful aggregate error/completeness state, privacy-safe capture outcomes,
cross-surface lifecycle explanations, and complete reset/backup boundaries.
Salary reporting, accessibility/device acceptance, recurring planning,
category budgets, and the data-footprint screen follow as P1 work. Cloud sync,
account aggregation, and opaque AI coaching are explicitly deferred or rejected
under the local-first product direction.

T-172e is **CLOSED WITH WAIVER** for this review: the product owner marked an
external representative participant session and interactive accessibility
acceptance not required, so no further T-172e pickup is planned. This does not
convert the operator smoke record into human evidence.
A non-destructive device check on 2026-08-01 reached the wireless Motorola edge
50 pro and confirmed the app process was alive; `READ_SMS`/`RECEIVE_SMS` were
granted and notifications were denied. A follow-up smoke run visited Home,
Activity, Sort, and Trends without changing app data, then restored Trends.
The tabs and primary controls rendered, but the persistent bottom navigation
covered lower content on all three content-heavy screens; the same overlap
reproduced at font scale 1.3 on Home, Activity, and Trends. A read-only
Activity-to-detail route opened and returned successfully, while a `DEBUG`
ribbon remained visible. This is device screen-smoke evidence, not a TalkBack,
large-text acceptance, or participant pass.

## Current architecture

| Layer | Implemented state | Primary source |
| --- | --- | --- |
| Android platform | SMS permission, live receiver, inbox paging, notifications, document picker, model bridges, Keystore plugin | `android/app/src/main/kotlin/`, `packages/paisatrack_keystore/` |
| Capture | Live/history/resume ingestion, template → generic → optional local-LLM parsing, deduplication, typed misses | `lib/capture/` |
| Domain/data | Drift schema v7 on SQLCipher, repositories, corrections/rules, identities, payment-source semantics | `lib/data/`, `lib/enrichment/` |
| Intelligence | Recurring, anomalies, forecasts, insights, local classifier, grounded assistant | `lib/intelligence/` |
| Presentation | Riverpod state with four-tab Bloom shell and task sheets/pages | `lib/features/`, `lib/core/widgets/` |

See `docs/architecture.md`, `docs/schema.md`, and `docs/privacy.md` for the
normative boundaries.

## Feature status

| Product area | Actual state | Important gap |
| --- | --- | --- |
| Onboarding and SMS permission | Implemented; users may continue without SMS and can open app settings after permanent denial | Device acceptance for permission/recovery remains |
| Live/history/resume SMS capture | Implemented, local, paged, idempotent, and manual scans report scanned/rejected/unknown/accepted/parsed/unparsed/created/already-known counts; retained failures store only an allowlisted reason and parser version, suppress same-version retries, and retry after parser upgrades; Settings and Activity now expose shared permission status cards that refresh on app resume, alongside content-free retained-failure counts, reason buckets, retention disclosure, and inbox-scan retry | Device acceptance remains; targeted retry and live expiry refresh remain future hardening |
| Bank parsing | HDFC, ICICI, SBI, Axis, Central Bank, Kotak, IndusInd, Paytm, Punjab National Bank and generic coverage exist; sanitized salary-credit templates and sender-agnostic fallback are proven end to end; PNB has a public-source fixture matrix with an exact-parse gate; developer diagnostics expose content-free native live/batch filter and unknown-sender counters | Public PNB templates remain capped at 0.85 until device confirmation; counters reset with the app process; further bank breadth still requires sanitized evidence and exact parser assertions |
| Transactions | Manual entry, detail, correction, scope, provenance, CSV export, search/filter UI, explicit Activity page exhaustion, strict Activity keyset paging, continuation while filtered | Activity search still covers only the loaded page; SQL-backed cross-page search remains future work, and query failures still need actionable error states |
| Review/Sort | Card/list presentation, keep/change/skip controls with DB-first updates | Queue remains capped at 100; cursor/persistence work is T-153 |
| Dashboard | SQL aggregates, shared local calendar/eligibility contract, period selector, truthful guidance, global monthly budget prototype, recurring totals | Error states remain incomplete |
| Trends/recurring | Deterministic aggregates, stored insights, recurring series/statuses | Eligibility diagnostics are absent |
| Categories and identities | Category manager, SQL-backed paged payee labels/search, payment-source naming/ownership/exclusion | Duplicate suggestions remain review-only; several secondary screens retain legacy surfaces |
| Assistant | Deterministic intents and queries with guarded local-model fallback | Model status/management is not exposed truthfully in Settings; conversation accessibility is incomplete |
| Encrypted storage/recovery | SQLCipher, Keystore-backed passphrase, durable key persistence, typed recovery | Physical-device backup/SAF acceptance remains release evidence |
| Backup/import | v3 archive compatibility plus authenticated v2 chunked document envelope; paged row serialization, transactional restore, progress/cancellation, bounded 32 MiB encrypted file, 16 MiB payload, 50,000-row/table and 200,000-row/archive limits; only non-expired raw SMS is exported/restored; shipped Argon2id profile is required | Physical SAF/provider acceptance and release evidence remain T-170b/T-171 |
| Delete everything | Deletes database/native state, DB key, Dart settings, and import markers | Physical-device erasure acceptance remains |
| Accessibility | Reduced motion and some semantics/responsive tests exist | Touch targets, TalkBack labels/order, contrast, large text, and device acceptance are incomplete |
| Offline behavior | Core finance and inference work offline after optional model downloads | Background/device-only behavior is not fully accepted on physical hardware |
| Release/distribution | Release signing guard and rotation/rollback documentation exist | CI/device test lanes and distribution evidence remain |

The stored global monthly budget and merchant-cap prototype are not T-098.
T-098 is a future per-category, per-month budget feature and depends on a shared
net-spending contract.

## Known limitations by implementation priority

1. **P1 — Error truthfulness:** never map loading/query errors to empty or zero
   financial state.
2. **P1 — Data correctness:** retain parity tests for the shared local calendar
   and analytics-eligibility contract as future analytics paths are added.
3. **P1 — Scale:** move Activity/Review/Payee search and paging to SQL; stream
   backups; replace quadratic owned-transfer reconciliation.
4. **P1 — Privacy:** exclude expired/raw SMS from backups, protect lock-screen
   notification content, and move pending answers out of plaintext preferences.
5. **P2 — Maintainability:** remove the database↔duplicate-rule import cycle,
   split oversized repositories/screens, and migrate money from `double`/REAL
   to integer paise.

Exact owners, dependencies, acceptance criteria, and next actions are in
`TASKS.md`.

## Intended versus actual outcome

| Intended outcome | Actual gap |
| --- | --- |
| Trustworthy spending guidance | Dashboard can mix periods and render sample financial claims as real |
| Recoverable, user-controlled local data | Some errors point to reset; delete-everything is incomplete |
| Automatic SMS capture with clear recovery | Permanent denial recovery actions do not open system settings |
| Complete, scalable financial history | Activity and Review operate on bounded client-side windows |
| Private, production-ready Android app | Notification/native state remains outside the erase boundary; release is debug-signed |
| Accessible Bloom experience | Visual redesign is ahead of semantics, touch targets, contrast, and device acceptance |
| Category budgeting | Only an overall-budget/cap prototype exists; category budgets remain planned |

## Active work

The Bloom migration is partially complete. Capability-preserving corrections,
SMS lookup, period selection, backup completeness, HDFC/ICICI templates,
correction matching, Review list scaffolding, and several responsive tests have
landed in the worktree. Remaining Bloom and release gaps are normalized into
`TASKS.md`; the original audit/addendum are archived as design inputs.

## Verification snapshot

Historical full-suite evidence, recorded on 2026-07-26:

- `flutter test --no-pub --concurrency=1`: **490/490 passed**.
- Android `:app:testDebugUnitTest` and
  `:paisatrack_keystore:testDebugUnitTest`: **passed**.
- `flutter analyze --no-pub`: **one lint**, at
  `test/features/insights/insights_recurring_test.dart:102`.

Current workspace verification, 2026-07-29:

- Focused T-155/T-156 regression suite: **25/25 passed**.
- `flutter analyze --no-pub`: **no issues found**.
- GitNexus clean rebuild: status confirms the current `main` commit is indexed
  and up to date.

- GitNexus taint enumeration remains unavailable because the index has no PDG
  layer; this is not evidence that taint risks are absent.

Not verified: physical-device SMS delivery/resume, permanent-denial settings
round-trip, WorkManager execution, TalkBack, large text, model download/inference
on target devices, profile/release performance, and store signing/distribution.

## Planned rework

Two design documents now sit ahead of the roadmap, decomposed into 59 PR-sized
task briefs under `docs/tasks/` with a one-line index in `TASKS.md`.

- `docs/sms-intelligence-design.md` (T-131…T-144) — the capture and truth layer.
  Its highest-priority finding is live in the current code: `LlmExtractor`
  returns `amount`, `direction`, and `ts` and validates only plausibility, never
  that the value appears in the source message, so a misread amount can persist
  as a settled transaction at confidence 0.75. T-131 closes this with an
  evidence-span verification boundary.
- `docs/ui-gaps-and-redesign.md` (T-145…T-154) — conformance with the accepted
  Bloom handoff plus reported defects. The most visible: no `BloomCategoryTile`
  call site passes `iconName`, so every category row in the app renders the
  generic fallback glyph while showing the correct hue.

`PLAN.md` records eight open product decisions, each with a default already in
effect so none of them blocks implementation.

## Documentation-change verification (2026-07-26, later session)

The changes in this session are documentation only — `PLAN.md`, `TASKS.md`,
`docs/sms-intelligence-design.md`, `docs/ui-gaps-and-redesign.md`, and
`docs/tasks/`. No file under `lib/`, `android/`, or `test/` was modified.

Verified: task-brief and board index parity (59 sub-tasks, no orphans), all
sub-task dependencies resolve to defined tasks, markdown tables and code fences
well-formed, and every code claim in both design documents re-checked against
source at `45a3546` plus the current worktree.

**Not verified in this environment**, and required before merge:

- `flutter analyze` / `flutter test` — the bundled SDK at `.tooling/flutter` is a
  macOS arm64 binary and cannot execute in a Linux sandbox.
- GitNexus `detect_changes()` — `tree-sitter` has no `linux/arm64` native build;
  only the cached `status` read succeeds.
- Android Gradle unit tests.

These must be run on the development machine before the branch merges.
