# Product Status

Status date: 2026-07-26  
Code baseline: `codex/bloom-redesign` at `45a3546`, including the current
uncommitted worktree

This is the source of truth for current product state. Normative technical
contracts live in the linked `docs/` files, future outcomes live in `PLAN.md`,
and unfinished delivery work lives only in `TASKS.md`.

## Outcome summary

PaisaTrack is a functional Android-first, local-first finance tracker built
around transactional SMS. Its capture, encrypted storage, correction,
categorization, recurring detection, deterministic analytics, grounded
assistant, backup, and most Bloom UI paths are implemented and covered by a
large host-side test suite.

It is not production-ready. The current Bloom UI can present fabricated or
mixed-period financial guidance, several data failures look like valid empty
states, permanent SMS-permission recovery is broken, generic database failures
lead to destructive recovery copy, delete-everything misses native state, and
release builds use debug signing.

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
| Onboarding and SMS permission | Implemented; users may continue without SMS | “Open settings” does not open Android app settings after permanent denial |
| Live/history/resume SMS capture | Implemented, local, paged, and idempotent | Failed/unparsed rows lack a durable automatic retry contract; device acceptance remains |
| Bank parsing | HDFC, ICICI, SBI, Axis, Central Bank, Kotak, IndusInd, Paytm and generic coverage exist | Unknown-sender drops are not measurable; real-bank breadth remains incomplete |
| Transactions | Manual entry, detail, correction, scope, provenance, CSV export, search/filter UI | Activity searches only the loaded 100-row window and converts query failures to empty state |
| Review/Sort | Card/list presentation, keep/change/skip controls | Queue is capped at 100; shared index can create false Inbox Zero; writes advance before success |
| Dashboard | SQL aggregates, period selector, global monthly budget prototype, recurring totals | Fabricated Blinkit insight/cap and fixed ₹48k setup; historical/custom periods mix with current-month advice |
| Trends/recurring | Deterministic aggregates, stored insights, recurring series/statuses | Error states and period semantics are incomplete; eligibility diagnostics are absent |
| Categories and identities | Category manager, payee labels, payment-source naming/ownership/exclusion | Payee aggregation remains unbounded; several secondary screens retain legacy surfaces |
| Assistant | Deterministic intents and queries with guarded local-model fallback | Model status/management is not exposed truthfully in Settings; conversation accessibility is incomplete |
| Encrypted storage/recovery | SQLCipher, Keystore-backed passphrase, schema repair migrations | Passphrase persistence is asynchronous/racy; generic DB errors route to key-loss reset |
| Backup/import | v3 encrypted archive includes all 12 schema tables; 12-character export floor | Whole archive is held in memory; raw SMS outlives normal retention inside backups |
| Delete everything | Deletes database files, DB key, Dart settings, and import markers | Native ask-answer preferences, notifications, and model/partial files survive |
| Accessibility | Reduced motion and some semantics/responsive tests exist | Touch targets, TalkBack labels/order, contrast, large text, and device acceptance are incomplete |
| Offline behavior | Core finance and inference work offline after optional model downloads | Background/device-only behavior is not fully accepted on physical hardware |
| Release/distribution | Debug and test builds work | Release uses debug signing; CI omits native Android tests and device lanes |

The stored global monthly budget and merchant-cap prototype are not T-098.
T-098 is a future per-category, per-month budget feature and depends on a shared
net-spending contract.

## Known limitations by implementation priority

1. **P0 — Financial truthfulness:** remove hardcoded Blinkit advice/cap and
   fixed ₹48k setup; prevent historical/custom periods from driving
   current-month “safe today” and runway.
2. **P0 — Recovery and erasure:** distinguish typed key loss from retryable
   database errors; complete native-state erasure; provide backup restore before
   reset.
3. **P0 — Permission and review flows:** open Android settings for permanent
   SMS denial; make Sort persistence-first and impossible to falsely complete.
4. **P0 — Release integrity:** configure production signing and fail release
   builds when credentials are absent.
5. **P1 — Error truthfulness:** never map loading/query errors to empty or zero
   financial state.
6. **P1 — Data correctness:** unify local calendar boundaries and the
   analytics-eligibility predicate across dashboard, forecasts, anomalies,
   insights, and ask-budget calculations.
7. **P1 — Scale:** move Activity/Review/Payee search and paging to SQL; stream
   backups; replace quadratic owned-transfer reconciliation.
8. **P1 — Privacy:** exclude expired/raw SMS from backups, protect lock-screen
   notification content, and move pending answers out of plaintext preferences.
9. **P2 — Maintainability:** remove the database↔duplicate-rule import cycle,
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

Verified in this workspace on 2026-07-26:

- `flutter test --no-pub --concurrency=1`: **490/490 passed**.
- Android `:app:testDebugUnitTest` and
  `:paisatrack_keystore:testDebugUnitTest`: **passed**.
- `flutter analyze --no-pub`: **one lint**, at
  `test/features/insights/insights_recurring_test.dart:102`.
- GitNexus: 315 indexed files, 5,687 symbols, 224 execution flows.
- GitNexus taint findings were unavailable because the index has no PDG layer;
  this is not evidence that taint risks are absent.

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
