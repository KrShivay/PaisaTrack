# Product Status

Status date: 2026-10-03
Code baseline: main at `016465d`; package version `0.1.7+2016`.
The published `0.1.7+2016` ARM64 release was installed in place on the owner
device (the previous `0.1.6+2015` build was also launched and checked there). Broad T-176/T-167c layout acceptance and other listed release
gates remain open. T-179a isolated lost-key recovery passed on a physical
device (2026-10-01).

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
[`docs/archive/reviews/product-value-review-2026-08.md`](archive/reviews/product-value-review-2026-08.md), with
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
| Domain/data | Drift schema v19 on SQLCipher; transactions, recurring series, and expected events retain source currency code/symbol evidence | `lib/data/`, `lib/enrichment/` |
| Intelligence | Currency-bucketed recurring, anomaly, forecast, insight, and grounded assistant paths; INR-only budgets disclose scope; no implicit FX conversion | `lib/intelligence/` |
| Presentation | Riverpod state with four-tab Bloom shell and task sheets/pages | `lib/features/`, `lib/core/widgets/` |

See `docs/architecture.md`, `docs/schema.md`, and `docs/privacy.md` for the
normative boundaries.

## Feature status

| Product area | Actual state | Important gap |
| --- | --- | --- |
| Onboarding and SMS permission | Implemented; users may continue without SMS and can open app settings after permanent denial | Device acceptance for permission/recovery remains |
| Live/history/resume SMS capture | Implemented, local, paged, idempotent, and manual scans report scanned/rejected/unknown/accepted/parsed/unparsed/created/already-known counts; retained failures store only an allowlisted reason and parser version, suppress same-version retries, and retry after parser upgrades; Settings and Activity now expose shared permission status cards that refresh on app resume, alongside content-free retained-failure counts, reason buckets, retention disclosure, and inbox-scan retry | Device acceptance remains; targeted retry and live expiry refresh remain future hardening |
| Bank parsing | HDFC, ICICI, SBI, Axis, Central Bank, Kotak, IndusInd, Paytm, Punjab National Bank and generic coverage exist; sanitized salary-credit templates and sender-agnostic fallback are proven end to end; PNB has a public-source fixture matrix with an exact-parse gate; developer diagnostics expose content-free native live/batch filter and unknown-sender counters | Public PNB templates remain capped at 0.85 until device confirmation; counters reset with the app process; further bank breadth still requires sanitized evidence and exact parser assertions |
| Transactions | Manual entry, detail, correction, source-currency-aware display and CSV export, search/filter UI, explicit Activity page exhaustion, strict Activity keyset paging, continuation while filtered | Activity search still covers only the loaded page; SQL-backed cross-page search remains future work, and query failures still need actionable error states |
| Review/Sort | Card/list presentation, keep/change/skip controls with DB-first updates and shared correction/undo sequencing | Queue remains capped at 100; cursor/persistence work is T-153 |
| Dashboard | SQL aggregates, shared local calendar/eligibility contract, period selector, truthful loading/error states, period and eligibility disclosure, known exclusions, local-data coverage caveat, separate foreign/unknown source-currency subtotals, global monthly budget prototype, recurring totals | Bank-wide capture completeness cannot be known from local records; INR-only budget math excludes other currencies |
| Trends/recurring | Deterministic evidence-backed claims power the Trends feed and local Trends inbox; recurring series/statuses and currency buckets remain separate; insight text is rendered from claims | Only valid, fresh supported claims appear; legacy rows without retained currency evidence remain unknown |
| Categories and identities | Category manager, SQL-backed paged payee labels/search, payment-source naming/ownership/exclusion | Duplicate suggestions remain review-only; several secondary screens retain legacy surfaces |
| Assistant | Deterministic intents and queries with guarded local-model intent fallback; payee matching uses whole-phrase identity evidence and clarifies ambiguity; answers disclose their counting scope | Conversation accessibility remains incomplete; VPA-only rows can still display raw VPAs in other surfaces |
| Encrypted storage/recovery | SQLCipher, Keystore-backed passphrase, durable key persistence, typed recovery | Physical-device backup/SAF acceptance remains release evidence |
| Backup/import | v3 archive compatibility plus authenticated v2 chunked document envelope; paged row serialization, transactional restore, progress/cancellation, bounded 32 MiB encrypted file, 16 MiB payload, 50,000-row/table and 200,000-row/archive limits; only non-expired raw SMS is exported/restored; transaction links, counterparties, category hierarchy, expected events, and durable SMS dispositions round-trip | Physical SAF/provider acceptance remains open; Ready T-195 proposes changing linked-source SMS expiry and backup inclusion |
| Delete everything | Deletes database/native state, DB key, Dart settings, and import markers | Physical-device erasure acceptance remains |
| Accessibility | Reduced motion and some semantics/responsive tests exist | Touch targets, TalkBack labels/order, contrast, large text, and device acceptance are incomplete |
| Offline behavior | Core finance and inference work offline after optional model downloads | Background/device-only behavior is not fully accepted on physical hardware |
| Release/distribution | Public production-signed ARM64 `0.1.7+2016` / code `4016` download was hash-verified against the installed artifact; cold launch and bounded checks were recorded on `0.1.6+2015` | Landscape/2×/three-button recheck, data-integrity checks, CI/device test lanes, store distribution, and broader physical acceptance remain; see [release evidence](release-signing.md) |

The stored global monthly budget and merchant-cap prototype are not T-098.
T-098 is a future per-category, per-month budget feature and depends on a shared
net-spending contract.

## Known limitations by implementation priority

1. **P1 — Error truthfulness:** never map loading/query errors to empty or zero
   financial state.
2. **P1 — Data correctness:** retain parity tests for the shared local calendar
   and analytics-eligibility contract as future analytics paths are added.
3. **P1 — Scale:** move Activity/Review search and paging to SQL; stream
   backups; replace quadratic owned-transfer reconciliation.
4. **P1 — Privacy:** implement Ready T-195's owner decision to retain linked
   source SMS beyond 30 days; protect lock-screen notification content and move
   pending answers out of plaintext preferences.
5. **P2 — Maintainability:** remove the database↔duplicate-rule import cycle,
   split oversized repositories/screens, and migrate money from `double`/REAL
   to integer paise.

Exact owners, dependencies, acceptance criteria, and next actions are in
`TASKS.md`.

## Intended versus actual outcome

| Intended outcome | Actual gap |
| --- | --- |
| Trustworthy spending guidance | Dashboard states its selected period, spending eligibility, known exclusions, and that records missing from PaisaTrack cannot be detected |
| Recoverable, user-controlled local data | Some errors point to reset; delete-everything is incomplete |
| Automatic SMS capture with clear recovery | Permanent denial recovery actions do not open system settings |
| Complete, scalable financial history | Activity and Review operate on bounded client-side windows |
| Private, production-ready Android app | Notification/native state remains outside the erase boundary; the published release has install/launch verification only, while data-integrity, recovery, accessibility, and store-release acceptance remain incomplete |
| Accessible Bloom experience | Visual redesign is ahead of semantics, touch targets, contrast, and device acceptance |
| Category budgeting | Only an overall-budget/cap prototype exists; category budgets remain planned |

## Active work

The original Bloom audit and addendum are archived as design inputs. The
remaining active design references are [SMS intelligence](sms-intelligence-design.md)
for open T-133/T-143 work and [UI gaps](ui-gaps-and-redesign.md) for open
T-149/T-151/T-154 work. The active board and current implementation state are
in `TASKS.md` and the feature table above.

## Verification snapshot

ARM64 release artifact and physical launch, 2026-09-30:

This is an earlier release snapshot; current release evidence is in
[release-signing.md](release-signing.md).

- The public `0.1.3+2011` ARM64 APK from commit
  `6ac898f564bfd307455a1b7201ab229a3fe09c80` was verified at 56,750,764 bytes
  with SHA-256
  `218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`, package
  `com.paisatrack`, effective code `4011`, ARM64-only ABI, and the production
  certificate recorded in `docs/release-signing.md`.
- On the motorola edge 50 pro (Android API 36), `adb install -r` succeeded. The
  installed base APK matched the published artifact hash, and
  `firstInstallTime` remained `2026-09-26 22:20:54`. This confirms an in-place
  package replacement; no private records were inspected, so it does not claim
  stored-data integrity.
- `MainActivity` launched and remained resumed. A recent filtered
  AndroidRuntime/linker log sample had no app fatal or native-load failure
  markers. This launch did not exercise optional inference paths. T-193 physical
  preview/apply/undo, T-194 storage/cold-start measurement, and the separate
  responsive, capture, and recovery acceptance gates remain open.

ARM64 published release install check, 2026-10-01:

- The signed `0.1.3+2012` release from source commit
  `9f966992f8665c4f7fea72882af1270cb34b3c3b` passed package/version/code,
  production-signer, ARM64 ABI, native-library packaging, ZIP-integrity, and
  alignment checks. It was published on `apk-downloads` in commit
  `79614386e4f5271c5ccefc67eca66368642fb7ae`. SHA-256 is
  `d028507574978ede386a5c3a1560415f8551f502887ad87f89ed20f2da0bd403`.
- `adb install -r` succeeded on the motorola edge 50 pro. The installed base APK
  matched the release hash and signer; `firstInstallTime` remained
  `2026-09-26 22:20:54`. This confirms in-place replacement only, not
  stored-data integrity.
- The first launcher request remained behind keyguard. After the owner unlocked
  the phone, Ask composer and close behavior passed bounded 1×, 1.5×, and 2×
  portrait checks with the real IME; one 2× scroll exposed one prompt control.
  Landscape and other routes remain untested. T-176/T-167c physical acceptance
  remains open. See the
  [owner-phone install report](reports/release-v2012-owner-phone-install-2026-10-01.md).

T-187 source-currency fidelity, reviewed and shipped on 2026-09-29:

- Full Flutter suite: **1,030/1,030 passed**; `flutter analyze --no-pub`,
  changed-file Dart formatting, and `git diff --check` clean.
- Independent review passed on `a5e2e61`; no physical-device or APK work was
  part of this change. Legacy rows without source evidence remain unknown, and
  bare `$` remains a separate unknown-code bucket.

Historical full-suite evidence, recorded on 2026-07-26:

- `flutter test --no-pub --concurrency=1`: **490/490 passed**.
- Android `:app:testDebugUnitTest` and
  `:paisatrack_keystore:testDebugUnitTest`: **passed**.
- `flutter analyze --no-pub`: **one lint**, at
  `test/features/insights/insights_recurring_test.dart:102`.

PV-02 verification on main, 2026-09-27:

- Dashboard aggregate corpus parity and dashboard/shell rendering suite:
  **16/16 passed**. The SQL aggregate test seeded all 20 transactions currently
  in `corpus.json` and pinned eligible and excluded row IDs as well as totals.
- `flutter analyze --no-pub`: **no issues found**; `git diff --check` clean.
- After correcting the dashboard navigation geometry regression, the definitive
  full host suite `flutter test --no-pub --concurrency=1` passed **764/764**;
  captured exit code was **0**.
- GitNexus `detect-changes --scope all`: 8 files / 14 indexed symbols, LOW risk,
  no affected processes. The repository-wide flow inventory is bounded and
  omitted candidates are not evidence of unaffected paths; dashboard callers
  and related tests were checked directly.

- GitNexus taint enumeration remains unavailable because the index has no PDG
  layer; this is not evidence that taint risks are absent.

- The existing corpus `long_history` descriptor claims 125 rows but contains
  only two. PV-02 parity covers the full current corpus; 125-row breadth and
  performance remain unverified until the fixture is expanded.

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
  Bloom handoff plus reported defects. (The earlier `BloomCategoryTile`
  fallback-glyph defect is resolved: call sites now pass `iconName`, and
  `CategoryVisuals.iconFor` also resolves an icon from `categoryId` when none is
  passed, so category rows render the correct glyph and hue.)

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

## Documentation audit — 2026-09-26

This planning review is source inspection, not a new device acceptance pass.
[Smart assistance](plans/smart-transaction-assistance.md) (T-177) remains
proposed; T-178a is complete and T-178b–d remain proposed in the
[grounded AI plan](plans/grounded-ai-validation.md).

- Standard categorizer wiring omits the merchant-memory and LLM-suggestion
  callbacks despite helper implementations. Treat T-140 historical completion
  as component work, not proof of active production learning.
- The assistant spending-query parity gap was closed in T-178a; see the current
  [assistant contract](assistant-nlq.md) and [architecture](architecture.md).
- T-178a delivered evidence-checked claims and fair comparisons. Forecast
  capture gaps and range calibration remain T-178b work.
- Conflicting board/brief status (notably T-143) must be reconciled with tests;
  this cleanup does not close uncertain implementation work.

The feature matrix above retains historical acceptance context; use current
source and the task board to verify individual implementation claims.
