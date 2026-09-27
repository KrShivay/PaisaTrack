# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

## In Review

- [ ] T-180 [P1] Persist Weekly Review confirmations and make undo restore
  persisted state.
  - Acceptance: Keep writes `confirmed` even when no feedback row is needed;
    the transaction disappears from `watchReviewQueue` after a fresh query.
    Undo writes `needs_review`, restores one row in the query and one visible
    card, and the undo controller consumes its action once. Cover the empty-
    feedback path and a status change alongside a real feedback edit.
  - Dependencies: none. No schema or migration change.
  - Privacy: status stays in the existing local database; no new data or
    retention.
  - Rollback: revert the focused repository/test change; persisted status
    values remain compatible with the existing review query.
  - Verification: repository/widget focused tests 26/26; full Flutter suite
    786/786; `flutter analyze --no-pub` and `git diff --check` clean. GitNexus
    change analysis: 5 files, 8 symbols, LOW risk, no affected processes.

- [ ] T-179a (@codex) [P0] Recover safely from a lost database key.
      Verification: 768 Flutter tests passed; analyzer and diff check clean;
      Android keystore unit tests and app Kotlin compile passed; API 35 ARM64
      emulator restored a synthetic archive through the real Keystore selector
      into SQLCipher, reopened the active generation, and verified legacy bytes
      remained unchanged. MainActivity relaunched successfully on emulator.

- [ ] T-176 [P1] Apply global bottom-inset contract to all screens.
      Module: all primary screens (Dashboard, Activity, Review, Insights,
      Settings, Assistant, Review/Sort card view).
      Gap: content at the bottom of each screen underlaps the bottom navigation
      bar; FABs and action button rows are not consistently lifted above it.
      Verification: focused inset suite 11/11, full Flutter suite 764/764,
      analyzer clean, `git diff --check` clean. Widget coverage exercises
      gesture inset scrolling, three-button nested Activity/Sort geometry,
      and Manual Entry with the keyboard open. AVD live nav/keyboard acceptance
      is inconclusive because API 35 SystemUI/IME did not expose navigation
      insets or render the keyboard; logcat has no PaisaTrack crash.
      Next: review the test-only diff; repeat live navigation/keyboard checks
      after safe physical-device recovery.

## Ready

<!-- P1 tasks ready for next phase -->

### Scale, privacy, and maintainability

- [ ] T-115 (@codex) [P1] Profile startup, import, and model memory.
      Module: bootstrap, capture, LiteRT-LM.
      Depends: signed profile/release build and target device.
      Next: record cold start, 10k-message import, baseline/navigation/model PSS,
      native/GPU caches, and idle/background release evidence.
- [ ] T-118 (@codex) [P2] Explain recurring ineligibility.
      Module: recurring detector/repository/UI.
      Depends: structured eligibility reason model.
      Next: show per-merchant progress, cadence/amount gaps, and fragmented
      identity warnings rather than a bare empty state.
- [ ] T-130 (@codex) [P2] Reduce architectural coupling and numeric risk.
      Module: data/domain architecture.
      Depends: staged migrations.
      Gap: database↔duplicate-rule import cycle, oversized repository/screens,
      O(n²) owned-transfer reconciliation, and monetary `double`/SQLite REAL.
      Next: introduce domain DTOs, split reads/commands/corrections, replace
      transfer scan with indexed SQL, and plan integer-paise migration.

### Accessibility, security, and release
- [ ] T-128 (@codex) [P1] Complete accessibility and failure-state coverage.
      Module: shell and all primary Bloom screens.
      Depends: stable P0 flows.
      Gap: unlabeled gesture controls, missing selected semantics, sub-48dp
      targets, light-theme contrast failure, weak large-text/semantics tests,
      and several errors rendered as empty states.
      Next: use semantic Material controls, ≥48dp targets, corrected tokens,
      1.5×/2× and multi-viewport widget tests, then TalkBack acceptance.
- [ ] T-090 (@codex) [P4] App lock.
      Module: app lifecycle/security.
      Depends: T-122/T-124 recovery contracts.
      Next: design launch/resume lock with unavailable-biometric and recovery
      paths that do not weaken SQLCipher.
- [ ] T-091 (@codex) [P4] Privacy-safe home widget.
      Module: Android widget.
      Depends: T-090.
      Next: define locked/unlocked disclosure and a configurable aggregate-only
      surface.
- [ ] T-094 (@codex) [P5] Distribution and portfolio release package.
      Module: release/product.
      Depends: T-090, T-115, T-125, T-128.
      Next: signed release, SMS-permission declaration or maintained sideload
      path, screenshots, privacy/architecture story, rollback checklist.

### Planned product outcomes

- [ ] T-102 (@codex) [P2] Local statement import and reconciliation.
      Module: new statement import/reconciliation module.
      Depends: source fingerprint and reconciliation schema.
      Next: specify CSV preview, account mapping, idempotency, guarded matching,
      ambiguity review, and transactional rollback.
- [ ] T-100 (@codex) [P2] Reimbursement, refund, and reversal tracking.
      Module: transaction relationships and analytics.
      Depends: shared net-spending contract from T-126.
      Next: design additive full/partial/many-link schema and explained net
      totals without mutating source transactions.
- [ ] T-101 (@codex) [P3] Recurring calendar and future-message detection.
      Module: capture and expected-event/recurring domain.
      Depends: expected events stored separately from settled transactions.
      Next: design reminder deduplication, debit settlement matching, snooze,
      cancel, missed, and price-change states.
- [ ] T-098 (@codex) [P3] Monthly category budgets.
      Module: dedicated budget schema/repository/UI.
      Depends: T-100 and T-126.
      Gap: the current overall monthly budget/merchant-cap prototype is not this
      feature and uses `baselines`.
      Next: design per-category/per-month limits, net refund/reimbursement
      semantics, remaining/threshold/projection state, and migration away from
      prototype storage.
- [ ] T-096 (@codex) [P3] Tolerant free-text category resolution.
      Module: assistant/category identity.
      Depends: stable category aliases.
      Next: add typo-tolerant matching that refuses ambiguity.

### Planned rework — task briefs in `docs/tasks/`

Full detail lives in one brief per parent ticket. Read `TASKS.md` to pick a task,
then `docs/tasks/T-NNN.md` for **only the sub-task you claimed** — typically
60–110 lines. Do not read the design documents unless a brief points you at a
section. See `docs/tasks/README.md` for the format.

Sub-task ids suffix the parent (`T-146a`). Parent ids are containers and are
never worked directly. Sizes: `~S` under half a day, `~M` up to a day, `~L` split
further before claiming.

#### SMS intelligence — `docs/sms-intelligence-design.md`

Phase A blocks B; B blocks C and D.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-143c1** | P1 | ~M | Shadow table and isolated runner | T-143a/b |
| **T-133a** | P1 | ~L | Shape scoring and quarantine store | T-129 |
| **T-133b** | P1 | ~M | "Messages we couldn't read" + retry on upgrade | T-133a |

Completed briefs are mapped in `docs/archive/planning-cleanup-2026-09.md`;
T-140's production integration gaps are handled by T-177a/b.

#### UI gaps — `docs/ui-gaps-and-redesign.md`

T-152a unblocks four screens. T-150a precedes the Ask rebuild. T-153a precedes
T-154a.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-151b** | P2 | ~S | Bubble geometry and verdict answers | T-151a |
| **T-151d** | P2 | ~M | Thinking, model-missing, no-answer states | T-151b |
| **T-151e** | P3 | ~M | Inline charts and follow-up chips | T-151b |
| **T-154b** | P2 | ~M | Inline corrections + guess refresh before Keep | T-154a |
| **T-149a** | P3 | ~M | Profile shell and personalisation | — |
| **T-149b** | P3 | ~M | Habits and money shape | T-149a |
| **T-149c** | P3 | ~S | Data footprint and privacy posture | T-149a |

Completed T-145a/b, T-146a/b, T-147a/b, T-148a/b, and T-152a are mapped in
`docs/archive/planning-cleanup-2026-09.md`.

Follow `PLAN.md` for delivery priority: finish T-176 and T-179a physical-device
acceptance, then T-177a. T-157b and PV-02 passed independent review and were
removed from the active board. Recheck T-153a integration only if its
implementation is still needed; T-151b remains open pending a supported
affordability intent and deterministic verdict contract.

#### Flutter refactor, no behavior change — `docs/tasks/`

Scoped to presentation helpers, the oversized `transaction_detail_screen.dart`,
Riverpod boundaries, and shallow render-only tests. T-159a is complete; see the
historical mapping in `docs/archive/planning-cleanup-2026-09.md`.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-156c** | P2 | ~M | Standardize TransactionDetailScreen's presentation | T-158c |
| **T-158b** | P2 | ~M | Extract `TransactionDetailController` | T-157b |
| **T-158c** | P2 | ~M | Extract sub-widgets into `detail/` | T-158a (complete) |
| **T-159c** | P3 | ~M | Convert remaining shallow render tests to behavioral | T-158c |

Completed T-156b, T-157a/b/c, T-158a/d, and T-159a/b are mapped in
`docs/archive/planning-cleanup-2026-09.md`.

## Backlog

<!-- Groom future work here before promoting it to Ready. -->

Before promoting an item to `Ready`, keep its brief actionable and include
acceptance evidence, dependencies, privacy impact, and rollback path. Keep one
implementation task in progress at a time.

#### Capture correctness and observability

- [ ] T-160d [P1] Extract reusable paged-list controller/state from Activity without changing review-queue behavior; characterize loading, error, retry, and exhaustion states first.
- [ ] T-161e [P1] Add end-to-end tests for scan outcomes: newly created, already known, parsed-but-duplicate, unparsed, individual failure, and native rejection.
- [ ] T-162b [P1] Define sender-onboarding evidence format (header, template fingerprint, fixture, expected result) and add a review gate before expanding `SmsFilter` allowlist.
- [ ] T-162c [P1] Add unsupported-sender telemetry aggregated only by safe reason/category; prove personal-number bodies and identifiers are never persisted or logged.
- [ ] T-162d [P2] Add deterministic employer/payroll alias recognition layered after parser evidence verification; require credit direction and account/channel context.
- [ ] T-163a [P1] Make the SMS scan entry a reusable capture-status component for Activity, Settings, onboarding completion, and empty states.
- [ ] T-163b [P2] Add scan cancellation/resume semantics with checkpoint preservation and explicit user-visible partial-result state.

#### Product-value research and review

Historical review: `docs/product-value-review-2026-08.md` and
`docs/product-quality-review.md`; T-172e's evidence boundary and waiver are in
`docs/tasks/T-172.md`. Target-device screen-smoke is an observation, not a
human-validation pass.

#### Product-value implementation briefs

The review produced dependency-ordered follow-ons; groom one at a time before
promoting it to `Ready`. Full contracts, owners, rollback paths, and acceptance
metrics are in `docs/tasks/T-172.md`.

- [ ] PV-01 [P0] Complete full-history keyset search/filter and timestamp contract. Depends: T-160b–d, T-164a–b, T-164e.
- [ ] PV-03 [P0] Add privacy-safe capture outcome ledger, reason buckets, and bounded retry. Depends: T-161a–e, T-162a–c.
- [ ] PV-04 [P0] Unify lifecycle, duplicate, transfer, refund, and excluded-source explanations. Depends: T-164c–d, T-135.
- [ ] PV-05 [P0] Share correction/undo and complete backup/reset/raw-SMS/native-artifact recovery proof. Depends: T-159a, T-157b, T-170a–b.
- [ ] PV-06 [P1] Add salary income semantics and reversible source correction. Depends: T-162a, T-166a–b.
- [ ] PV-07 [P1] Apply the accessible primary-flow contract and device matrix. Depends: T-167a–h.
- [ ] PV-08 [P1] Add the data-footprint disclosure and release review package. Depends: T-169b, T-171a–b.

#### Smart transaction assistance — `docs/plans/smart-transaction-assistance.md`

- [ ] T-177a [P1] Audit production integration, provenance, and baseline accuracy.
- [ ] T-177b [P1] Integrate confirmed payee memory with a P2P eligibility guard.
- [ ] T-177c [P1] Complete correction scopes, rule conflicts, and undo.
- [ ] T-177d [P1] Add paged grouped review and persistent deferral.
- [ ] T-177e [P2] Reuse categories and support evidence-only optional descriptions.
- [ ] T-177f [P1] Shadow-evaluate and stage opt-in assistance release.
- [ ] T-177g [P3] Assess local receipt/screenshot matching.

#### Grounded AI

- [ ] T-178a [P1] Validate insight claims and comparison correctness against source data.
- [ ] T-178b [P1] Validate forecast ranges, data coverage, and backtesting.
- [ ] T-178c [P2] Add typed Hinglish assistant intents over validated results.
- [ ] T-178d [P2] Add local evaluation, performance gates, and staged release.

#### Transaction integrity, data model, and performance

- [ ] T-164a [P0] Add repository tests for keyset ordering under identical timestamps, deleted rows, duplicate-suppressed rows, and newly inserted rows between pages.
- [ ] T-164b [P1] Move Activity filtering/search to SQL with indexed fields and paged results; preserve every current filter semantic.
- [ ] T-164c [P1] Add explainable visibility flags for deleted, duplicate-suppressed, pending, reversed, transfer, and excluded-payment-source transactions.
- [ ] T-164d [P2] Add “show excluded” Activity filter and detail explanation without letting excluded rows alter spending/budget totals.
- [ ] T-164e [P0] Establish one transaction timestamp-display contract used by list grouping/rows, detail, dashboard, search/date filters, imports, and SMS capture; resolve local-time versus UTC conversion once at the presentation boundary, preserve the stored instant, and add India midnight/DST-equivalent/timezone-change regression tests proving every surface shows the same calendar date and time.
- [ ] T-165a [P1] Profile 10k/50k transaction Activity rendering and query latency on release hardware; record thresholds and baseline evidence.
- [ ] T-165b [P1] Replace O(n²) owned-transfer reconciliation with an indexed SQL candidate query and adversarial same-amount/date tests.
- [ ] T-165c [P2] Plan and ADR an integer-paise migration, including lossless conversion, compatibility, rollback, and migration tests.
- [ ] T-165d [P2] Split `TransactionRepository` reads/commands/corrections behind domain DTOs; prove existing provider and migration behavior.
- [ ] T-166a [P1] Implement explicit salary income analytics card and period totals that include credits but never treat transfers/refunds as salary.
- [ ] T-166b [P2] Add income source review/correction flow with undo and optional historical relabel preview.

#### UI quality, accessibility, and refactoring

- [ ] T-167a [P0] Audit every primary screen for loading, error, empty, and retry states; replace misleading empty states with actionable errors.
- [ ] T-167b [P0] Add semantic labels, selected state, and 48dp minimum targets to custom Activity, Dashboard, Settings, and Review controls.
- [ ] T-167c [P1] Add 1.5x/2x text and narrow/wide viewport widget tests for all primary transaction flows.
- [ ] T-167d [P1] Replace bespoke gesture-only controls with semantic Material controls or equivalent explicit semantics.
- [ ] T-167e [P0] Audit every root-tab screen, nested sheet, and detail route for FAB/action-button overlap with the bottom navigator, gesture area, keyboard, or system navigation inset; record viewport screenshots and exact affected widgets.
- [ ] T-167f [P0] Introduce one shared safe-area/FAB placement contract that reserves bottom-navigation height, system gesture insets, keyboard insets, and minimum touch clearance; migrate Dashboard, Activity, Review, Insights, Settings, and all nested action sheets without per-screen magic offsets.
- [ ] T-167g [P1] Add behavioral widget tests at small Android, gesture-navigation, keyboard-open, large-text, and landscape viewports proving every primary FAB/button is visible, tappable, and not hit-tested beneath bottom navigation.
- [ ] T-167h [P1] Add golden/regression coverage for root navigation plus floating actions in light/dark themes; fail on visual intersection or <48dp exposed tap target.
- [ ] T-167i [P2] Standardize bottom-sheet action bars and scroll padding on the same inset contract, including long forms, validation errors, and hardware-keyboard layouts.
- [ ] T-167j [P0] Define and implement one app-wide back-navigation contract: Android back button, predictive-back gesture, and in-app back controls dismiss transient UI first, then pop every previously visited route one by one; once on a root tab, return to Home; once on Home, show an accessible “Press back again to exit” snackbar and exit only on a second back action within a documented timeout. Preserve tab history deliberately, avoid accidental exit, and add widget/integration tests for sheets, nested details, all root tabs, Home fallback, timeout expiry, keyboard-open state, and gesture/button parity.
- [ ] T-168a [P1] Extract `TransactionDetailScreen` pure presentation helpers and subwidgets behind characterization tests (T-159a prerequisite).
- [ ] T-168c [P2] Route remaining bespoke sheets/dialogs through Bloom helpers and add API-level presentation tests.
- [ ] T-168d [P2] Establish a visual-regression golden suite for Activity, SMS scan, salary income, errors, and dark/light themes.
- [ ] T-169a [P1] Add a dedicated transaction-import progress model shared by onboarding, Settings, and Activity; remove duplicated display counters.
- [ ] T-169b [P2] Add a privacy/data-footprint screen explaining local SMS retention, parse status, backup inclusion, and safe deletion.

#### Reliability, privacy, and release readiness

- [ ] T-170a [P0] Add fault-injection tests for database-write, parser, channel, lifecycle, and native inbox query failures; prove retries are bounded and idempotent.
- [ ] T-170b [P1] Verify raw-SMS expiry, backup exclusion, deletion, and recovery behavior with device-backed acceptance evidence.
- [ ] T-170c [P1] Add release-build smoke tests for permission recovery, first import, resume catch-up, 10k history paging, and salary credit visibility.
- [ ] T-170d [P2] Create a manual QA matrix for supported senders/templates, unsupported-sender telemetry, and false-positive privacy checks.
- [ ] T-171a [P1] Add CI shards for Flutter unit/widget, Android unit, migration, and fixture-contract tests with deterministic failure artifacts.
- [ ] T-171b [P2] Publish performance and accessibility acceptance budgets in docs, then gate release candidates on measured evidence.

## Board rules

- Keep exactly one instance of every `##` workflow heading; handoff automation
  parses them literally.
- Keep only unfinished work. Remove an item after implementation and required
  verification are complete.
- Move at most one implementation task to `In Progress`.
- `In Review` is temporary and contains only unresolved verification/review.
- Record current state in `docs/product-status.md`, durable decisions in ADRs,
  and completed evidence in Git history or `docs/archive/`.
