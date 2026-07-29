# Current Handoff

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.

## 2026-07-30 — T-126 complete: calendar and spending semantics

- Added `FinancialCalendar` (local calendar → UTC query instants) and the
  shared `FinancialEligibility` contract. Dashboard periods/repository,
  burn-rate, anomaly, insights, and Ask quota now use the same settled-spend
  definition and injected boundary service.
- Added India midnight/month-boundary and lifecycle-exclusion coverage.
  Repaired the category-picker keyboard-inset test harness so it asserts the
  sheet's outer padding instead of an unrelated inner padding.

## 2026-07-29 — T-156a approved: dialog consolidation

- T-156a is complete and removed from `TASKS.md`. `showBloomDialog` now
  owns every production dialog presentation; Dashboard and developer SMS
  dialogs no longer bypass it. The Dashboard behavior test proves validation
  and persistence; existing developer, recovery, and payee tests prove their
  confirm/cancel actions.
- Verification: `flutter analyze --no-pub`, focused dialog tests, full
  `flutter test --no-pub`, and `git diff --check` pass. The raw-call audit
  finds no `showDialog(` outside `bloom_dialog.dart`.

## 2026-07-29 — Board reconciliation and dialog consolidation

- Reconciled `TASKS.md` to merged history. Removed completed P0 work
  (T-121–T-125), SMS work (T-131a–c, T-132a–c, T-134a–c, T-135a–c,
  T-136a–c, T-137a–b, T-138a–c, T-139a–b, T-140a–c, T-141a, T-142a,
  T-144a–b), and refactor work T-155a–c from the unfinished board.
- Rebuilt GitNexus from a clean index after stale-cache recovery. The graph
  identifies `showBloomDialog` in the `Build → ShowBloomDialog` flow; no
  unrelated flow is affected.

## 2026-07-28 — Flutter refactor plan (no code changed)

- Read-only audit for a requested refactor: duplicated category/icon/color
  resolution, sheet/dialog API consolidation, scattered threshold constants,
  the oversized `transaction_detail_screen.dart` (1,352 lines), Riverpod
  boundary violations, and shallow render-only tests. No `.dart` files were
  touched — this was a planning session only.
- Findings written up as five new parent tickets, `docs/tasks/T-155.md`
  through `T-159.md` (16 sub-tasks total), indexed in `docs/tasks/README.md`
  and `TASKS.md` under "Flutter refactor, no behavior change." Each sub-task
  cites exact file:line evidence gathered during the audit.
- Category icon/color resolution (`lib/core/theme/category_visuals.dart`) and
  numeric thresholds (`lib/core/constants.dart`) already have a correct
  canonical source each — the real gap is inline literals elsewhere that
  redeclare or coincidentally match those values instead of referencing them
  (T-155), plus a missing touch-target size token (T-155b, feeds T-128).
- **Board hygiene finding, corrected on this pass:** T-145a, T-145b, T-146a,
  T-146b, T-147a, T-147b, T-148a, T-148b, and T-152a were listed as open on
  `TASKS.md` but are already merged to `main` (verified via `git log` — PRs
  #38, #39, #45, #47–#52 — and by reading the current source at each cited
  line). Removed from the board and dependency references updated
  accordingly. The SMS-intelligence table (T-131…T-144) shows the same
  staleness pattern on spot-check (e.g. T-131a is also merged) but was not
  re-audited in full — flagging as a fast-follow rather than expanding this
  session's scope.
- Highest-risk item in the new plan: T-157b (extracting the category-
  correction + undo controller, duplicated four times across
  `transaction_detail_screen.dart` and `weekly_review_screen.dart`) has almost
  no existing behavioral test coverage. T-159a (characterization tests) is
  sequenced before it for exactly that reason.

## 2026-07-26 — Full product/code/documentation audit

- Audited actual Flutter, Android, Keystore, capture, data, intelligence, and UI
  behavior with GitNexus plus parallel product, architecture/docs, and
  data/security reviews.
- Highest-risk gaps: fabricated/mixed-period dashboard guidance, failure-as-empty
  state, broken permanent SMS permission recovery, false/optimistic Sort
  completion, generic-error destructive recovery, incomplete erasure,
  asynchronous/racy DB-key persistence, and debug-signed releases.
- Created `docs/product-status.md` as the current-state source of truth.
- Rebuilt `TASKS.md` with one machine-readable workflow structure, removed
  completed T-109/T-110 work, narrowed T-108 to its actual residual scope, and
  mapped every active gap to module/dependency/priority/next action.
- Archived superseded reviews and migration plans after extracting unfinished
  work.

## Verification

- `rtk proxy ./.tooling/flutter/bin/flutter test --no-pub --concurrency=1`:
  490/490 passed.
- `./gradlew :app:testDebugUnitTest
  :paisatrack_keystore:testDebugUnitTest`: passed.
- `rtk proxy ./.tooling/flutter/bin/flutter analyze --no-pub`: no issues found
  after resolving the eight previously reported info-level findings.
- GitNexus taint enumeration unavailable because the current index has no PDG
  layer; do not treat this as a clean security result.

## Next action

T-121..T-125 are complete (see "Completed P0 Blockers" in `TASKS.md`); this
note was stale and is corrected here. Current priority backlog is T-126/T-129
(`TASKS.md` → Ready). The new Flutter refactor track (T-155..T-159) is
independent and unscoped for priority against it; start with T-159a
(regression tests) if picked up, since it gates T-157b.
