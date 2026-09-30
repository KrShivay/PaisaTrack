# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

- [ ] T-176 [P1] Apply the global bottom-inset contract to all screens.
  - Acceptance: exercise Trends, Settings (including Not transactions), Ask,
    transaction detail, nested sheets, and floating actions through their real
    routes. Verify final rows and actions clear the floating navigation in
    gesture and three-button modes, and remain visible/tappable with the
    keyboard, compact/landscape viewports, and large text.
  - Verified acceptance slice: a route harness mounts the production
    `HomeFloatingNavPill`, `BloomBottomInset` adapter, and actual Trends route.
    The Trends final section clears the actual pill at 24dp gesture and 48dp
    three-button insets on 402×874, and at 568×320 landscape with 1.5× text.
    The harness uses a nested Navigator and the production nav widget because
    mounting `HomeShell` in this fixture leaves Drift stream cleanup timers
    pending; shell lifecycle integration remains open. No production inset gap
    was demonstrated, so production code is unchanged.
  - Settings/Not transactions slice: five real-route checks open Settings,
    tap its Not transactions action, and assert the final synthetic history row
    clears the production navigation pill at 24dp/48dp insets on 402×874,
    320×568 at 2× text, and 568×320 at 1.5×/2× text. The inherited
    `MediaQuery.padding.bottom` gives the history `ListView` its bottom inset;
    no inset fix was needed. Tapping the row exposed and fixed a `setState`
    callback returning `_load()`'s Future, and the compact 2× layout exposed
    and fixed the trailing amount consuming the entire `ListTile` width. The
    test unmounts the route and closes its in-memory Drift database inside the
    test body so cleanup does not defer `StreamQueryStore.markAsClosed`'s
    `Timer.run` until Flutter's post-test teardown.
  - Ask compact-keyboard slice: the production full-screen Ask route now has
    a focused test at 320×568 and 2× text, then dynamically resizes to 320×348
    with zero residual inset (the keyboard area is counted once, matching
    `adjustResize`). The compact Ask-only header keeps the composer visible,
    retains a 48dp close target, and leaves the transcript scrollable; normal
    height keeps the full header. The earlier 42px overflow figure came from
    a fixture that applied both the 348dp resize and a 220dp inset. A corrected
    route-size-only fixture still reproduced a real compact-height issue: the
    full header title and subtitle wrapped to 138dp and 155dp, leaving only
    23dp for the AssistantScreen. A submitted user message now verifies the
    actual transcript ListView has positive scroll extent at 320×348/2× text;
    its prompt panel is capped to leave transcript space in 96–240dp content
    heights. The Ask-specific compact header addresses the route constraint
    without changing the shared sheet scaffold.
  - Still open: transaction detail and nested sheet integration with the shell
    pill, Ask modal-route acceptance on device, remaining compact/landscape
    combinations, and physical phone QA. No emulator, private SMS/DB data,
    phone mutation, or APK change.
  - Focused verification: global bottom-inset route tests 8/8, including five
    Settings/Not transactions cases; Ask route plus AssistantScreen tests 9/9;
    full Flutter suite 930/930; detail/Note and
    full-screen sheet baseline 17/17; `flutter analyze --no-pub`, formatter,
    diff check, and GitNexus detect-changes clean. The Ask-only change is LOW
    risk with no affected processes. No emulator, private SMS/DB data, phone
    mutation, or APK change.

## Ready

- [ ] T-177a [P1] Audit production integration, provenance, and baseline accuracy.
  - Bounded milestone: add a local chronological replay/report contract and
    synthetic fixtures that exercise live, history, and resume provider wiring;
    document per-field provenance and deliberate path differences. Keep T-177a
    open for real-data holdout, device capture coverage, and rollout gates.
  - Active fix: unreviewed `auto` rows are not accuracy evidence and must never
    lower the persisted category threshold. Lowering requires an explicit
    user-confirmation feedback event with category-prediction provenance;
    corrections remain error evidence and may raise the threshold. Historical
    v1/v2 adaptive values are ignored so prior silent-row lowering cannot
    persist. Completed chronological 50-outcome cohorts are fingerprinted;
    changed outcomes replay those cohorts from the static default. If undo or
    category removal leaves fewer than 50 eligible outcomes, the learned value,
    count, and fingerprint are cleared.
  - Synthetic milestone adds live/history/resume provider fixtures, a
    chronological explicit-label report contract, and the provenance matrix in
    `docs/reports/T-177a-capture-provenance.md`. T-140/T-143 status and their
    production integration limits are reconciled there. Remaining T-177a gates:
    real chronological holdout, physical capture coverage, and a reviewed
    capture-decision-version contract. Synthetic arithmetic is not a baseline.
    Independent review passed without blocker. The resume fixture calls the
    catch-up runner directly; app-resume lifecycle and known-SMS-boundary
    behavior remain unverified alongside physical live/resume capture.
  - Verification: threshold tests 17/17; repository/detail/template-ledger
    tests 38/38; full Flutter suite 903/903; analyzer, changed-file formatting,
    and diff check clean. Same-count correction, v1/v2 state invalidation,
    multiple cohorts, undo to 49 outcomes, and full category removal are
    covered. GitNexus impact: `AdaptiveThresholdPolicy` HIGH (47 symbols / 4
    flows), `TransactionRepository` CRITICAL (80 / 43 direct), `TransactionDetail`
    CRITICAL (77 / 40 direct), `TransactionDetailScreen` HIGH (42 / 18 direct),
    `TemplateTrustLedger` HIGH (90 / 12 direct); exact ledger `refresh` is
    UNKNOWN with 2 dropped callers, text search corroborates call sites.
    Detect-changes reports 25 symbols, 9 files, 4 processes, MEDIUM. No schema,
    phone, or APK changes.
  - Detail now has a separate evidence-backed parse-confirm action; it never
    changes transaction status/category and intentionally does not count as
    category-threshold evidence. Broad provider/provenance/baseline audit is
    still open.

## In Review

- [ ] T-193 [P1] Repair legacy currency only from retained source evidence.
  - Context: rows captured by v0.1.2+2006 predate T-187. Current parsing maps
    `Rs.` to INR, but the v18 migration leaves older null-currency rows
    unchanged and `ingestBatch` skips already-known SMS IDs.
  - Acceptance: transaction detail offers a non-mutating preview and explicit
    reversible apply only when both currency fields are null, linked SMS is
    still within retention, amount span evidence matches the body and stored
    paise value, and one adjacent INR token is unambiguous. Revalidate on apply;
    alter only currency code/symbol. USD, bare `$`, manual/imported/unknown,
    deleted/duplicate, stale, mismatched, or expired source stays unchanged.
  - Scope: user-triggered per-row repair, no schema or migration change; works
    against restored data only when linked source/evidence survived. No auto
    action during migration, restore, or startup. All backup/restore tests use
    synthetic data; physical repair UI confirmation remains pending.
  - Verification: repair service/detail tests 22/22; focused backup and repair
    service suites 40/40; full Flutter suite 915/915; `flutter analyze --no-pub`,
    changed-file formatting, and diff check clean. New encrypted chunked-backup
    test proves retained SMS and amount evidence survive restore for
    preview/apply/undo, while an expired source is detached and remains
    ineligible. GitNexus detect-changes: 9 documentation section symbols in
    TASKS, WORKLOG, and T-193 notes, LOW risk, no affected processes; the test
    file has no indexed symbols. The added compatibility test changes no
    production code, schema, migration, or release artifact. Source-backed repair
    received independent review with no blocker; the encrypted restore
    compatibility-test commit also passed independent review. No physical
    repair UI confirmation has been performed.
  - Release follow-up: signed `0.1.3+2010` is installed in place on the ARM64
    phone (effective code 4010; `firstInstallTime` remained
    `2026-09-26 22:20:54`; the app launched with live PID 16774 and the newest
    exit-info entry was `PACKAGE UPDATED`). Physical preview/apply/undo
    acceptance remains open.

- [ ] T-167c [P1] Fix large-text overflows and cover primary transaction flows.
  - Acceptance: fix confirmed 320×568/2× overflow in HomeShell navigation,
    Activity header, and Trends header. Add narrow/wide viewport checks at
    1.5×/2× text for navigation, Activity/list and transaction entry/detail
    flows, and Trends. Preserve visible streak count and period context in
    compact Dashboard layouts, label Ask accessibly, and keep long foreign-
    currency amounts readable. Preserve visible navigation, accessible labels,
    and minimum 48dp tap targets.
  - Scope: flexible/wrapping/adaptive layout fixes only; no device mutation.
  - Verification: responsive route suite 42/42; focused changed-screen/inset
    suite 56/56; reviewer follow-up focused suite 24/24; full Flutter suite
    894/894; `flutter analyze`, changed-file formatting, and `git diff --check`
    clean. GitNexus follow-up impact: Dashboard MEDIUM, nav MEDIUM, Ask LOW,
    Activity row MEDIUM; shared `BloomAmount` impact was HIGH and its code was
    left unchanged. Follow-up detect-changes: 8 files, 9 symbols, 0 processes,
    LOW. HomeShell route fixture cleanup
    hangs on Drift streams, so navigation pill geometry, semantics, and tap
    behavior are covered directly. Dashboard coverage asserts visible streak /
    period values at 320 / 402 px and 1.5× / 2×; Ask semantics and two-line
    foreign-currency amounts are covered. Physical-device acceptance remains
    open.
  - Independent review pending.

- [ ] T-179a (@codex) [P0] Recover safely from a lost database key.
      Verification: 768 Flutter tests passed; analyzer and diff check clean;
      Android keystore unit tests and app Kotlin compile passed; API 35 ARM64
      emulator restored a synthetic archive through the real Keystore selector
      into SQLCipher, reopened the active generation, and verified legacy bytes
      remained unchanged. MainActivity relaunched successfully on emulator.

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

- [ ] T-188 [P2] Define Trends notification inbox lifecycle.
  - Acceptance: Specify when a threshold crossing creates an inbox item, how
    repeated crossings deduplicate, how users move/return an item, and what
    Clear all means. Reuse existing insight evidence and dismissal state where
    possible; test period changes, recomputation, repeated thresholds, and
    clear-all persistence before implementation.
  - Dependencies: coordinate with T-178a insight claims; do not treat the
    current `dismissed` bit as a notification inbox without defining states.
  - Privacy: local-only aggregates and state; no notification body with raw SMS.
  - Rollback: keep existing Trends insight feed available if inbox is disabled.

- [ ] T-190 [P2] Plan credit-card purchase, bill, payment, refund, and failure
      accounting. **Do this last among the newly requested tasks.**
  - Acceptance: Produce a grounded scenario map for card purchases, statement
    generation, bill payments, full/partial refunds, failed/reversed payments,
    and statement reconciliation. Define which source rows remain immutable,
    lifecycle/duplicate links, settled-spend and available-credit boundaries,
    user review, backup, and undo requirements; identify gaps in T-100/PV-04.
    Planning only; no schema or implementation until separately approved.
  - Dependencies: reuse T-100 refund/reimbursement links and PV-04 lifecycle
    explanation; inspect actual card and payment-source data first.
  - Privacy: synthetic scenarios only; no live statements or SMS.
  - Rollback: planning artifact only; no runtime behavior changes.

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

- [ ] T-167b [P0] Add semantic labels, selected state, and 48dp minimum targets to custom Activity, Dashboard, Settings, and Review controls.
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
