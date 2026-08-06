# Current Handoff

## 2026-08-02 — T-117 SQL payee identity index complete

- Added schema-15 payee_evidence, rebuildable from authoritative transaction
  evidence, with ingestion/correction hooks and backup-restore rebuilds.
- Replaced unbounded Dart payee grouping/search with SQL aggregation, alias
  filtering, unresolved/unlabeled filters, two-query alias loading, and
  keyset paging. Duplicate suggestions are review-only and do not merge data.
- Added repository, migration, realistic-volume, paging, and UI coverage.
- Verification: analyzer clean; focused T-117 suite **12/12**; GitNexus
  refreshed to **7,893 nodes / 16,893 edges / 252 flows** and final change
  detection completed. The full Flutter suite remains **1 failure** in the
  unrelated `exclusion_explanation_test.dart` baseline (expected 500, actual
  5500).

## 2026-08-02 — T-127 streaming backup/import complete

- Added an additive authenticated v2 binary envelope with 60 KiB data chunks,
  unique per-chunk nonces, AAD binding, and a final manifest binding chunk and
  byte counts. Existing v1 JSON/AES-GCM imports remain supported.
- Export now pages Drift rows into newline-delimited records; import authenticates
  and restores those rows inside one transaction, with rollback on corruption,
  cancellation, expiry violations, or row/size limits.
- Replaced the Settings backup path with bounded Android document sessions and
  progress/cancellation callbacks. The native gateway never retains the full
  backup or calls `readBytes()` for the production backup path.
- Added protocol-integrity, progress, cancellation, document-session, and
  transactional restore coverage. Focused backup/gateway suites and Android
  app unit tests pass; physical SAF/provider acceptance remains release evidence
  under T-170b/T-171.

## 2026-08-02 — T-127 bounded encrypted backup slice

- Added explicit 32 MiB encrypted-file, 16 MiB decoded-payload, 50,000-row
  per-table, and 200,000-row total ceilings. File length is checked before
  reading a selected file; ciphertext and archive row counts are checked
  before KDF derivation or database mutation.
- Restricted imports/exports to the shipped Argon2id profile
  (19,456 KiB / parallelism 1 / iterations 2 / 32-byte hash). Export now
  filters raw SMS at the captured `purge_after` boundary, and restore skips
  expired rows. Archive versions 1–3 and rows without parser metadata remain
  compatible.
- Added ADR 0008 plus backup/privacy/product-status documentation and
  non-vacuous tests for size, KDF, row-limit, retention, and legacy metadata
  behavior. This bounded slice was followed by the completed streaming envelope
  and session gateway implementation above.


This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.

## 2026-08-02 — T-161d implemented: SMS permission refresh and status cards

- Added an app-root lifecycle refresher that re-reads SMS permission on every
  resume, including after Android app settings changes.
- Added one shared permission-status card to Settings and Activity. It shows
  granted, denied, permanently denied, unavailable, and checking states, with
  the matching runtime-request, app-settings, or recheck action.
- Reconciled the stale T-129 parent: T-161a–c now cover its durable
  capture/diagnostic scope, so T-129 was removed from `TASKS.md`; T-161d is
  the only implementation item in progress.
- Verification: focused provider/card/lifecycle/Settings/Activity suite
  **19/19**; full Flutter suite **630/631**, with only the known
  `test/features/transactions/exclusion_explanation_test.dart` failure
  (expected 500, actual 5500); analyzer clean, format and diff checks clean,
  and GitNexus refreshed with task-scoped change detection before commit.

## 2026-08-02 — T-108 slice implemented: native SMS filter counters

- Added a content-free diagnostics channel for native live/batch filter
  rejections and unknown-sender drops; the existing developer Unparsed SMS
  screen displays the four counters and states their process-lifetime scope.
- Kept the sender allowlist unchanged: additional bank coverage still requires
  sanitized evidence and exact parser assertions.
- Verification: focused Dart diagnostics/backfill suite **33/33**, diagnostics
  screen suite **13/13**, Android `:app:testDebugUnitTest` **passed**, full
  Flutter suite **633/634** with only the known
  `test/features/transactions/exclusion_explanation_test.dart` failure
  (expected 500, actual 5500), analyzer clean, and Dart format clean.
  GitNexus impact was LOW before edits; final change detection and commit
  remain required.

## 2026-08-02 — T-108 evidence-backed bank coverage added

- Added PNB/PNBSMS/`ONE-PNB` sender recognition and loaded
  `assets/templates/pnb.json` into the live template matcher. The registry
  covers dated UPI credits, dated UPI debits with optional time, and compact
  dated credits.
- Added seven sanitized public-source fixtures derived from the TRAI RTI SMS
  annex, each retaining only masked account suffixes and transaction fields;
  every expected result records public provenance and the source URL. The
  dedicated T-108 gate requires at least seven positives and >=90% exact
  normalized output, while the shared fixture suite checks all-bank coverage.
  Public reference IDs in the committed fixtures are deterministic sanitized
  values rather than copied identifiers from the source examples.
- Luna's bounded audit initially requested reference-ID sanitization, a tighter
  compact-credit boundary, and native sender-header tests; the follow-up audit
  approved all three fixes. Product-review/docs changes remained untouched.
- Verification: fixture suite **9/9**; Android `:app:testDebugUnitTest`
  **passed**; full Flutter suite **634/635**, with only the known
  `test/features/transactions/exclusion_explanation_test.dart` failure
  (expected 500, actual 5500); analyzer clean, format clean, and
  `git diff --check` clean. GitNexus refresh and staged change detection are
  completed before the task-scoped commit.

## 2026-08-02 — T-161c implemented: user-facing unreadable-message status

- Added `RawSmsRepository.watchRetainedFailures`, which selects only
  allowlisted failure reasons and unexpired metadata; it never loads bodies,
  senders, or identifiers. Expired rows stay out of the summary even before
  nightly deletion runs.
- Added the user-facing `UnreadableSmsScreen` under Settings → Data & Backup.
  It shows total counts, `unparsed` and `processing_error` buckets, the
  existing 30-day raw-message retention policy, and no raw message content.
- Added a retry affordance that opens the existing bounded inbox scan with
  `force: true`. Same-parser-version failures remain suppressed by T-161b;
  parser upgrades and the scan path make retained rows eligible without
  creating a second retry contract.
- Luna’s bounded audit found no privacy leak or high-risk edit in this scope;
  it flagged that retry is a full inbox scan and that live expiry refresh and
  targeted retry remain future hardening. No unrelated dirty review/docs were
  changed.
- Verification: focused unreadable/repository/SMS UI **7/7**; capture,
  backfill, developer diagnostics, and SMS lookup **53/53**; affected Settings
  **4/4**; `flutter analyze --no-pub` clean; Dart format clean; full Flutter
  suite **625/626**, with only the known
  `test/features/transactions/exclusion_explanation_test.dart` failure
  (expected 500, actual 5500); GitNexus impact completed before edits.

## 2026-08-01 — T-162a complete: salary-credit ingestion matrix

- Added a sanitized, data-driven matrix for HDFC and ICICI salary-credit
  templates plus a sender-agnostic generic salary-credit message. The test
  drives each case through the shipped `ParserCascade`, `Categorizer`, and
  `SmsIngestor`, asserting one credit transaction, amount, `income_salary`,
  processed raw SMS, and parser provenance.
- Luna initially requested changes for empty-matrix protection, parser-source
  assertions, and generic-path isolation. The matrix now asserts its expected
  unique cases, template IDs are checked exactly, and the generic case uses an
  unsupported synthetic sender with no template ID.
- Verification: focused salary/bank suite **23/23**; `flutter analyze
  --no-pub`, full Flutter suite, Dart format, `git diff --check`, and GitNexus
  change detection are completed before commit. The generic parser now gives
  salary credits a stable `Salary` payee label; no dependencies changed.
- T-162a is removed from `TASKS.md`; the next implementation task is T-161c,
  the user-facing retained-failure/retry surface.

## 2026-08-01 — T-161a complete: privacy-safe SMS scan outcomes

- Android inbox pages now return scanned, filter-rejected, unknown-sender, and
  accepted counts, including zero-count fields on an empty provider result.
  Missing senders are classified as unknown; missing bodies remain generic
  filter rejects. Existing bounded `(date,id)` cursor behavior is unchanged.
- Dart carries those page counts through `SmsImportProgress` and
  `SmsImportResult`, derives parsed/unparsed/created/already-known counts from
  the local ingestion boundary, and shows the complete breakdown during and
  after manual SMS scans. No raw bodies, senders, identifiers, or errors enter
  progress/result models or logs.
- Luna acceptance audit initially requested changes for the empty native
  payload and null-sender classification; both were fixed, and the follow-up
  Android suite passed **26/26**. This is why T-161a stayed open after the
  first focused pass.
- Verification: focused Dart capture/SMS suite **38/38**; `flutter analyze
  --no-pub` clean; Dart format and `git diff --check` clean; Android
  `:app:testDebugUnitTest` **26/26**; full Flutter suite **613/614**, with the
  same unrelated `exclusion_explanation_test.dart` aggregate expectation
  failure (expected 500, actual 5500). GitNexus MCP remained unavailable
  (`Transport closed`), so CLI `detect-changes` was used; it reports critical
  overall risk because this checkout contains unrelated user edits, while the
  expected SMS/Activity flows are the affected paths.
- Impact note: `SmsFilter.isAllowed` was HIGH-risk in the fallback impact
  report (16 direct callers, 2 processes), so its API and implementation were
  left untouched; counts use its existing batch unknown-sender counter.
- T-161a is removed from `TASKS.md`. Next unfinished priority is T-161b
  (durable capture retry/reason diagnostics).

## 2026-08-01 — T-161b complete: durable privacy-safe retry metadata

- Added schema-14 nullable `raw_sms.parser_version` and
  `raw_sms.failure_reason` columns. Every ingest attempt stamps the active
  parser version; expected misses persist `unparsed`, processing failures
  persist `processing_error`, and exception text never enters the database or
  progress models.
- Same-version failed rows are skipped. Retained failures are eligible again
  only after a parser-version increase, including incremental catch-up;
  successful rows and existing transactions remain idempotent.
- Added migration coverage for legacy databases with and without a `raw_sms`
  table, generated `database.g.dart` with a database-only Drift build filter,
  backup round-trip/legacy compatibility coverage, allowlist validation, and
  retention deletion coverage.
- Luna first requested changes for upgraded incremental retries and backup
  allowlist enforcement; both were fixed, and the final audit requested only
  then received the missing legacy-migration fixture coverage.
- Verification: focused capture/backup/migration/retention suite **53/53**;
  full Flutter suite **622/623**, with the same unrelated
  `exclusion_explanation_test.dart` aggregate expectation failure (expected
  500, actual 5500); `flutter analyze --no-pub`, Dart format, and
  `git diff --check` clean. GitNexus MCP remained unavailable (`Transport
  closed`), so CLI `detect_changes` was used; it reports critical aggregate
  risk because this checkout contains unrelated user edits. No dependencies,
  commits, or native code were changed for T-161b.
- T-161b is removed from `TASKS.md`. The next unfinished P0 in the capture
  workstream is T-162a (salary-credit fixture coverage); T-161c remains the
  user-facing follow-up.

## 2026-08-01 — LUNA-07 product-value review package

- Added the capability inventory, synthetic local-only corpus, execution
  register, user-job/comparable-product research, P0/P1/P2 scorecard,
  moderator script, implementation briefs PV-01–PV-08, and release cadence in
  `docs/product-value-review-2026-08.md`, `docs/tasks/T-172.md`,
  `docs/product-quality-review.md`, and
  `test/fixtures/product_review/corpus.json`.
- The conclusion is trust-first: full-history discovery, truthful aggregate
  states, capture observability, cross-surface integrity explanations, and
  complete reset/backup boundaries precede new intelligence.
- T-172e is **CLOSED WITH WAIVER**: the product owner marked representative
  participant sessions and interactive TalkBack/accessibility QA not required
  for this review. The operator/device observations remain recorded without
  being relabeled as human validation; no further T-172e pickup is planned.
  A read-only ADB check reached the wireless Motorola edge 50 pro (Android 16,
  1220×2712, font scale 1.0); SMS permissions were granted and notifications
  were denied. A later read-only smoke run visited Home, Activity, Sort, and
  Trends, then restored Trends without changing app data. The primary screens
  rendered, but the persistent bottom navigation covered lower content and a
  DEBUG ribbon was visible. A read-only Activity-to-detail route opened and
  returned; a reversible font-scale 1.3 pass reproduced the overlap on Home,
  Activity, and Trends. Font scale was restored to 1.0. No app data was cleared
  or mutated.
- Verification: corpus JSON and `git diff --check` passed; focused transaction/
  repository/manual-entry/activity suite **33/33 passed**. Current full Flutter
  suite is **610/611**, with the pre-existing exclusion aggregate failure in
  `test/features/transactions/exclusion_explanation_test.dart`; current
  `flutter analyze --no-pub` reports no issues. Android unit tasks were not
  rerun in this documentation/device-evidence continuation; the earlier
  recorded `:paisatrack_keystore:testDebugUnitTest` failure remains documented.
  No production code was changed for this review.

## 2026-08-01 — T-160c complete: filtered Activity continuation

- Preserved the Activity search/filter state while loading another page.
  When the current page has no filtered matches but the unfiltered page says
  `hasMore`, the empty state now keeps the Load more action available.
- Added a controllable page-controller widget regression proving an older
  matching transaction appears after loading and the search text remains
  active. Luna confirmed the root cause and narrow fix.
- Verification: focused Activity/repository/manual-entry suite **35/35**;
  analyzer clean; full Flutter suite **610/611**, with the same unrelated
  `exclusion_explanation_test.dart` aggregate expectation failure; GitNexus
  detect-changes completed through the CLI fallback while its MCP transport
  was unavailable.

## 2026-08-01 — T-160b complete: stable Activity keyset continuation

- Applied the Activity page cursor as a strict descending `(ts,id)` SQL
  predicate and added the `id` tie-breaker to newest-first ordering.
- Replaced Activity's shared limit expansion with an
  `ActivityTransactionPageController` that fetches one bounded page at a time,
  accumulates only opened pages, and preserves page membership when live
  inserts/deletes would otherwise move a continuation boundary.
- Added repository coverage for 1,000 mixed/tied timestamps, deleted and
  duplicate-suppressed rows, and an insert between page reads; added a
  controller regression for 201 rows and a between-page insert.
- Verification: repository **18/18**, controller **1/1**, and the focused
  Activity/repository/manual-entry suite **34/34**; `flutter analyze --no-pub`
  clean; `dart format --set-exit-if-changed` clean; `git diff --check` clean;
  full Flutter suite **609/610**, with the existing unrelated
  `exclusion_explanation_test.dart` aggregate expectation failure; GitNexus
  detect-changes completed through the CLI fallback while the MCP transport
  was unavailable. Luna acceptance audit **PASS**.
- Risk/DRY: the legacy `transactionListProvider` and limit state remain for
  dashboard/aggregate consumers; T-160d can extract the reusable paged-list
  controller after Activity behavior is characterized. Page snapshots are a
  deliberate consistency boundary; reopening Activity refreshes the page.

## 2026-08-01 — T-160a in review: explicit Activity page exhaustion

- Replaced Activity's `rows.length == limit` continuation heuristic with an
  explicit `ActivityTransactionPage` containing bounded rows, `hasMore`, and a
  privacy-safe `(ts,id)` cursor shape reserved for T-160b. The query fetches one
  look-ahead row and still excludes deleted and duplicate-suppressed rows.
- Activity now consumes the dedicated page provider; the legacy transaction
  list provider remains unchanged for dashboard/aggregate consumers. The SMS
  import action remains available with existing transactions.
- Luna review requested stronger visibility tests; added exact-100 terminal,
  101-row look-ahead, cursor-field, deleted-row, duplicate-suppression, and
  widget continuation coverage.
- Verification: focused repository/Activity/manual-entry suite **31/31**;
  `flutter analyze --no-pub` clean; `git diff --check` clean; full Flutter
  suite **607/608**, with the unrelated existing dashboard exclusion aggregate
  failure in `test/features/transactions/exclusion_explanation_test.dart`.
- Risk/DRY: no raw SMS enters the page model; provider plumbing duplicates the
  legacy stream temporarily and is intentionally consolidated under T-160b/d.

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
