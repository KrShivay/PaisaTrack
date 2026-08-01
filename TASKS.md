# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

<!-- Keep at most one implementation task here. -->

## Ready

<!-- P1 tasks ready for next phase -->
- [ ] T-129 (@codex) [P1] Add durable capture retry and privacy-safe diagnostics.
      Module: SMS backfill/ingestion, Android filter, SMS lookup/dev diagnostics.
      Depends: versioned retry reason/state.
      Gap: failed/unparsed rows count as known, import is marked complete after
      row failures, and live errors/unknown senders are not durably measurable.
      Next: persist content-free reason codes and retry version, retry bounded
      failures after parser upgrades, and expose accepted/rejected/failed counts.
- [ ] T-108 (@codex) [P2] Measure and extend bank sender/template coverage.
      Module: Android SMS filter, template registry, developer diagnostics.
      Depends: T-129 content-free native rejection counters.
      Implemented: HDFC/ICICI deterministic templates, sender allowlist entries,
      and sanitized tests are complete.
      Gap: senders rejected natively are invisible to Dart, and additional banks
      require evidence-backed fixtures.
      Next: expose unknown-sender counts without bodies/identifiers, then add
      bank coverage only from sanitized fixtures with exact parser assertions.

### Scale, privacy, and maintainability

- [ ] T-127 (@codex) [P1] Stream and bound encrypted backup/import.
      Module: backup service, document gateway, privacy.
      Depends: vNext archive format.
      Gap: picker and backup hold full ciphertext/plaintext/table copies in
      memory; KDF input allows 256 MiB before authentication; raw SMS can live
      indefinitely in backups.
      Next: enforce file/row/ciphertext limits now, accept known KDF profiles,
      exclude expired/raw SMS, then design chunked authenticated streaming with
      progress and compatibility tests.
- [ ] T-115 (@codex) [P1] Profile startup, import, and model memory.
      Module: bootstrap, capture, LiteRT-LM.
      Depends: signed profile/release build and target device.
      Next: record cold start, 10k-message import, baseline/navigation/model PSS,
      native/GPU caches, and idle/background release evidence.
- [ ] T-117 (@codex) [P2] Move payee-label aggregation/search to SQL.
      Module: payee label repository/UI.
      Depends: paged identity query.
      Gap: UI search exists, but the repository watches and groups the complete
      transaction history in Dart.
      Next: add SQL aggregation, unresolved/search filters, paging, and duplicate
      suggestions with realistic-volume tests.
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
| **T-143a** | P1 | ~S | `feature_flags` table | — |
| **T-143b** | P1 | ~M | Link-sequence and adversarial fixtures | — |
| **T-143c** | P1 | ~L | Shadow mode and on-device metrics | T-143a/b |
| **T-133a** | P1 | ~L | Shape scoring and quarantine store | T-129 |
| **T-133b** | P1 | ~M | "Messages we couldn't read" + retry on upgrade | T-133a |

Completed work is retained in Git history: T-131a–c, T-132a–c, T-134a–c,
T-135a–c, T-136a–c, T-137a–b, T-138a–c, T-139a–b, T-140a–c, T-141a,
T-142a, and T-144a–b.

#### UI gaps — `docs/ui-gaps-and-redesign.md`

T-152a unblocks four screens. T-150a precedes the Ask rebuild. T-153a precedes
T-154a.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-150a** | P2 | ~M | Extract prompt catalogue; test against validator | — |
| **T-150b** | P2 | ~M | Searchable, grouped empty state | T-150a |
| **T-150c** | P3 | ~S | Rotating composer chips | T-150a, T-151c |
| **T-151a** | P2 | ~M | Sheet presentation; remove the duplicate title | — |
| **T-151b** | P2 | ~S | Bubble geometry and verdict answers | T-151a |
| **T-151c** | P2 | ~S | Composer styling | T-151a |
| **T-151d** | P2 | ~M | Thinking, model-missing, no-answer states | T-151b |
| **T-151e** | P3 | ~M | Inline charts and follow-up chips | T-151b |
| **T-153a** | P2 | ~M | Ordered queue + cursor replaces the skip filter | — |
| **T-153b** | P2 | ~S | Back navigation through seen cards | T-153a |
| **T-153c** | P2 | ~M | Skipped end state, persistence, progress | T-153a |
| **T-154a** | P2 | ~M | Open transaction detail from the Sort card | T-153a |
| **T-154b** | P2 | ~M | Inline corrections + guess refresh before Keep | T-154a |
| **T-149a** | P3 | ~M | Profile shell and personalisation | — |
| **T-149b** | P3 | ~M | Habits and money shape | T-149a |
| **T-149c** | P3 | ~S | Data footprint and privacy posture | T-149a |

T-145a, T-145b, T-146a, T-146b, T-147a, T-147b, T-148a, T-148b, and T-152a are
implemented on `main` (see WORKLOG.md) and removed from this board per the
board rules below.

#### Suggested order

Ship first (small, independent, high visibility): T-150a.
Then the foundations everything else waits on: T-143a/b, T-131b/c, T-132a-c.

#### Flutter refactor, no behavior change — `docs/tasks/`

Scoped to duplicated category/icon/color resolution, sheet/dialog APIs,
scattered threshold constants, the oversized `transaction_detail_screen.dart`,
Riverpod boundary violations, and shallow render-only tests. Narrows T-130's
"oversized repository/screens" gap for these specific files; does not replace
T-130's data-layer/DTO scope. T-159a (regression tests) should land before
T-157b starts — it is the safety net for the riskiest extraction here.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-156b** | P2 | ~M | Route 4 bespoke sheet presenters through Bloom helpers | — |
| **T-156c** | P2 | ~M | Standardize TransactionDetailScreen's presentation | T-158c |
| **T-157a** | P2 | ~M | Move raw Drift writes out of recurring/insights screens | — |
| **T-157b** | P2 | ~L | Shared category-correction + undo controller | T-159a |
| **T-157c** | P3 | ~S | Relocate `suggestedCategoriesProvider` out of the screen | — |
| **T-158a** | P2 | ~M | Extract pure functions (chip ranking, exclusion, evidence) | — |
| **T-158b** | P2 | ~M | Extract `TransactionDetailController` | T-157b |
| **T-158c** | P2 | ~M | Extract sub-widgets into `detail/` | T-158a |
| **T-158d** | P3 | ~S | Verify exclusion-reason parity (UI vs. analytics SQL) | T-158a |
| **T-159a** | P1 | ~M | Characterize correction/undo behavior before extraction | — |
| **T-159b** | P2 | ~S | Unit tests for extracted pure functions | T-158a |
| **T-159c** | P3 | ~M | Convert remaining shallow render tests to behavioral | T-158c |

Suggested order: T-159a first (safety net) — then T-155/T-156/T-157a/T-158a
can proceed in any order (independent) — then T-157b — then T-158b/c — then
T-156c and T-159b/c last.

## Backlog

<!-- Groom future work here before promoting it to Ready. -->

### GPT-5.6 Sol high-thinking delivery queue

Each item is intentionally small enough for one focused implementation pass.
Before promoting an item to `Ready`, copy it to a task brief with file/symbol
anchors, acceptance tests, privacy impact, and rollback path. Do not run more
than one implementation item at once.

#### Luna high-level recursive workstreams

These are parent goals for a recursive Luna agent. They are not implementation
tasks: select their ordered child tickets below, delegate independent audits and
reviews, and close the parent only after every child has verification evidence.

- [ ] LUNA-01 [P0] Restore trustworthy transaction visibility: deliver T-160a–d, T-164a–d, and T-164e so the entire non-deleted history is discoverable, consistently dated, correctly filtered, paged without gaps, and explainable when excluded.
- [ ] LUNA-02 [P0] Make real SMS capture reliable and observable: deliver T-161a–e, T-162a–d, and T-163a–c with privacy-safe counters, supported-sender evidence, salary-credit coverage, permission recovery, and no raw-content leakage.
- [ ] LUNA-03 [P0] Make navigation predictable and unobstructed: deliver T-167e–j across every root tab, detail route, and sheet, with a shared inset contract, deterministic back behavior, and device/viewport proof that every primary action remains tappable.
- [ ] LUNA-04 [P1] Harden data correctness and scale: deliver T-165a–d, T-166a–b, and T-170a–d, preserving local-first semantics while proving large histories, income reporting, recovery, and deletion behavior.
- [ ] LUNA-05 [P1] Complete accessible, maintainable UI: deliver T-167a–d, T-168a–d, and T-169a–b using characterization tests before refactors, shared presentation primitives, and visual/semantics regression coverage.
- [ ] LUNA-06 [P1] Establish release confidence: deliver T-171a–b plus all unresolved P0/P1 verification evidence; produce a release-readiness report listing device tests, residual risks, privacy posture, and rollback steps.

#### Capture correctness and observability

- [ ] T-160d [P1] Extract reusable paged-list controller/state from Activity without changing review-queue behavior; characterize loading, error, retry, and exhaustion states first.
- [ ] T-161d [P1] Recheck SMS permission on app resume and make Settings/Activity status cards reflect granted, denied, and permanently denied states immediately.
- [ ] T-161e [P1] Add end-to-end tests for scan outcomes: newly created, already known, parsed-but-duplicate, unparsed, individual failure, and native rejection.
- [ ] T-162b [P1] Define sender-onboarding evidence format (header, template fingerprint, fixture, expected result) and add a review gate before expanding `SmsFilter` allowlist.
- [ ] T-162c [P1] Add unsupported-sender telemetry aggregated only by safe reason/category; prove personal-number bodies and identifiers are never persisted or logged.
- [ ] T-162d [P2] Add deterministic employer/payroll alias recognition layered after parser evidence verification; require credit direction and account/channel context.
- [ ] T-163a [P1] Make the SMS scan entry a reusable capture-status component for Activity, Settings, onboarding completion, and empty states.
- [ ] T-163b [P2] Add scan cancellation/resume semantics with checkpoint preservation and explicit user-visible partial-result state.

#### Product-value research and review

See the completed review package in `docs/product-value-review-2026-08.md`,
the task brief in `docs/tasks/T-172.md`, the recurring procedure in
`docs/product-quality-review.md`, and the synthetic corpus in
`test/fixtures/product_review/corpus.json`. LUNA-07 and T-172e are closed for
this review by explicit product-owner waiver: participant and interactive
accessibility evidence is not required and no further T-172e pickup is planned.
Target-device screen-smoke remains documented as observation, not a human pass.

#### Product-value implementation briefs

The review produced dependency-ordered follow-ons; groom one at a time before
promoting it to `Ready`. Full contracts, owners, rollback paths, and acceptance
metrics are in `docs/tasks/T-172.md`.

- [ ] PV-01 [P0] Complete full-history keyset search/filter and timestamp contract. Depends: T-160b–d, T-164a–b, T-164e.
- [ ] PV-02 [P0] Make dashboard aggregates truthful on loading/error and expose completeness/exclusions. Depends: T-126.
- [ ] PV-03 [P0] Add privacy-safe capture outcome ledger, reason buckets, and bounded retry. Depends: T-161a–e, T-162a–c.
- [ ] PV-04 [P0] Unify lifecycle, duplicate, transfer, refund, and excluded-source explanations. Depends: T-164c–d, T-135.
- [ ] PV-05 [P0] Share correction/undo and complete backup/reset/raw-SMS/native-artifact recovery proof. Depends: T-159a, T-157b, T-170a–b.
- [ ] PV-06 [P1] Add salary income semantics and reversible source correction. Depends: T-162a, T-166a–b.
- [ ] PV-07 [P1] Apply the accessible primary-flow contract and device matrix. Depends: T-167a–h.
- [ ] PV-08 [P1] Add the data-footprint disclosure and release review package. Depends: T-169b, T-171a–b.

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
- [ ] T-168b [P1] Consolidate repeated category correction + undo flows into one controller; prove behavior parity for detail and weekly review.
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
