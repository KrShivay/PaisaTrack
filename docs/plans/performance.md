# Performance, smoothness and test-speed plan

Status: Proposed, planning only — 2026-10-10. Covers T-203 (import flicker and
speed), T-208 (performance plan), T-210 (test-suite speed) and T-171b
(acceptance budgets). Briefs: [T-203](../tasks/T-203.md),
[T-208](../tasks/T-208.md), [T-210](../tasks/T-210.md),
[T-171](../tasks/T-171.md). Schema stays v20; no ADR is required by this plan
(indexes use the existing idempotent `CREATE INDEX IF NOT EXISTS` pattern;
an isolate-parsing ADR is *conditional*, see T-208g).

## Goal

The app feels instant and calm: cold start to a usable Dashboard in about two
seconds on the owner's Motorola edge 50 pro, no list or card ever blanking
back to a skeleton once data has been shown, a 10k-message first import that
finishes in about a minute while the UI stays at 60 fps with visible progress,
and a test suite that finishes fast enough to run on every change.

## Current state (evidence)

Details and `path:line` citations are in the briefs; the load-bearing facts:

1. **Flicker is dependency-driven reload, not Drift.** Riverpod 2.6.1
   (`pubspec.lock`), `AsyncValue.when` defaults to `skipLoadingOnReload:
   false`. `dashboardAggregateProvider` watches `transactionListProvider`
   (`lib/features/dashboard/dashboard_providers.dart:240`), so every list
   emission reloads six aggregate queries and flips the hero tile to a
   skeleton (`dashboard_widgets.dart:195-198`). 37 `.when(` sites exist: 18 UI
   sites and 19 copy-pasted provider-level database gates.
2. **Import already batches** per 200-message page in one transaction
   (`lib/capture/sms_ingestion.dart:617-621`) and suspends derived reads
   (`sms_backfill.dart:377,527`). The remaining costs are fan-out (every
   watched query re-runs per commit), the unthrottled end-of-import derived
   rebuild, a pure-debounce that can starve (`derived_reads_service.dart:
   88-106`), and no visible progress outside onboarding.
3. **Startup** runs `runApp` at once (`lib/main.dart:12-18`) but `PaisaTrackApp`
   routes only after DB open + seed + permission + settings
   (`lib/app.dart:55-79`); seeding and index checks run every launch
   (`database_provider.dart:215-216`, `database.dart:274-295`); the freshness
   snapshot does an unindexed `MAX(updated_at)` scan
   (`derived_reads_service.dart:337-350`).
4. **Queries**: Activity first page is a 3-way LEFT JOIN with only
   `idx_transactions_ts`; Dashboard is six aggregates; filtering/search is
   client-side until T-164b.
5. **Rendering**: Activity day sections are non-lazy `Column`s
   (`transactions_screen.dart:847-870`); `BloomSkeleton` repeats forever.
6. **Tests**: 220 files, one CI job running bare `flutter test`
   (`.github/workflows/ci.yml:55`), no tags/config, 177 `pumpAndSettle` calls
   in 34 files, 31 widget+DB files of which 8 use the Drift teardown helper;
   `docs/development.md:43` recommends `--concurrency=1`.

## Design

### 1. Calm UI (T-203)

- One helper (`whenStable`) so a loaded view never regresses to loading, one
  helper (`DatabaseGate.watchWith`) so the 19 gates stop being copy-pasted.
- Break the Dashboard's accidental dependency on the 100-row list; refresh via
  a throttled change tick with refresh semantics that keep the old value.
- `throttleLatest` (leading + trailing, newest value always delivered) applied
  only while `smsImportActiveProvider` is true; totals are never left stale.
- Derived reads: add `maxWait`, keep the suspension plus one guaranteed
  trailing run; timing logs for T-208.
- Activity: stable keys, "N new transactions" pill instead of silent freeze;
  global import progress banner in `HomeShell` (counts only).
- Acceptance is a widget test that mounts Dashboard, Activity and Review over
  an in-memory DB, runs a simulated 2,000-message import, and fails if any
  loaded view re-shows a skeleton/empty state, then compares final totals to
  SQL.

### 2. Measurable performance (T-208)

- Host proxies are the day-to-day guard: synthetic 50k ledger, EXPLAIN QUERY
  PLAN assertions (primary, deterministic), latency ceilings equal to the
  device budget (host is faster, so exceeding is a certain regression),
  rebuild-count and virtualisation tests, import throughput benchmark.
- Device measurement (owner phone, isolated install) via one script kit with
  the T-194 statistics (>= 30 samples, bootstrap CI, p95 descriptive).
- Fixes are evidence-driven: indexes only where a plan test shows a scan;
  startup trims only where the trace shows > 50 ms; parsing in an isolate only
  if parse+categorise >= 40% of per-message time *and* device frame gaps
  exceed 50 ms during import. WAL journal mode is deliberately *not* in scope:
  the WorkManager worker and backup/restore/recovery copy the database files
  (`database_recovery_service.dart:209,266`, `database_provider.dart:135`), so
  switching `journal_mode` needs its own ADR and device trial if the import
  profile shows write stalls.

### 3. Faster tests (T-210)

Measure first (JSON reporter splits load vs run per file), then pick: fix
`pumpAndSettle`-on-skeleton and unclosed-DB hazards, bundle files per folder
if load time dominates, duration-balanced shards for CI (T-171a), tags for
local selection. Every test still runs in required CI.

### 4. Budgets and release gate (T-171b)

One acceptance document and a machine-readable table; the checker fails a
release candidate on missing/mismatched evidence or a miss of a *calibrated*
budget; proposed budgets are advisory until the owner accepts the first
calibration run.

## Proposed budgets (all "proposed, to calibrate")

Reference device: owner's Motorola edge 50 pro (release/profile build, battery
not low, thermal normal). Percentiles are over >= 30 samples; gate on median
and bootstrap CI as in `docs/plans/release-gates.md`; p95/p99 descriptive.

| ID | Metric | Proposed budget | Host proxy | Device measurement |
|---|---|---|---|---|
| B-S1 | Cold start to first Flutter frame | p50 <= 1.5 s, p90 <= 2.0 s | startup-trace unit test (ordering only) | `am start -W` + trace (T-208l/h) |
| B-S2 | Cold start to interactive Dashboard (10k rows, no skeleton) | p50 <= 2.5 s, p90 <= 3.5 s | — | trace `dashboard_interactive` |
| B-S3 | Warm/resumed first frame | p50 <= 400 ms | — | `am start -W` warm |
| B-S4 | DB open + seed + index check | <= 400 ms (10k), <= 150 ms added by an index build is a one-time exception | seed-skip test, plan tests | trace `db_open_done`/`seed_done` |
| B-S5 | Derived-reads startup reconcile runs after interactive Dashboard and its freshness query <= 20 ms at 50k | ordering via provider test | query-plan test + latency ceiling | trace |
| B-Q1 | Activity first page (100 rows + joins), 50k rows | p90 <= 50 ms | plan test + `B-Q1` ceiling in `query_latency_perf_test` | T-165a |
| B-Q2 | Activity next page (keyset) | p90 <= 50 ms | same | T-165a |
| B-Q3 | Activity filter + search first page (after T-164b) | p90 <= 150 ms | plan + ceiling | T-165a |
| B-Q4 | Dashboard aggregate (6 queries), 50k rows | p90 <= 150 ms | plan + ceiling | T-165a |
| B-Q5 | Trends 6-month history | p90 <= 200 ms | plan + ceiling | T-165a |
| B-Q6 | Freshness snapshot | p90 <= 20 ms | plan (needs `updated_at` index) | trace |
| B-Q7 | Transaction detail by id | p90 <= 10 ms | plan | — |
| B-R1 | Frame build time, Activity fling / Dashboard | p90 <= 8 ms | rebuild-count tests | `gfxinfo` / frame summary (T-208j2) |
| B-R2 | Frame raster time | p90 <= 8 ms | — | same |
| B-R3 | Missed-frame ratio (> 16.7 ms), 10k-row Activity fling | <= 5% | — | same |
| B-R4 | Worst single frame (excl. first frame) | <= 100 ms | — | same |
| B-R5 | Rows built while scrolling | <= visible rows + cache extent, also for 5,000 rows in one day | `rebuild_budget_test` | — |
| B-R6 | Loaded view re-showing skeleton/empty during import | exactly 0 | `import_no_flicker_acceptance_test` | visual check |
| B-R7 | Idle Dashboard provider rebuilds in 5 s | 0 | `rebuild_budget_test` | — |
| B-I1 | Import throughput, 10k inbox, end-to-end | >= 200 msg/s (<= 50 s) | — | device (T-115) |
| B-I2 | Import throughput, host, in-memory DB | >= 1,000 msg/s floor (ceiling check, calibrate on first CI run) | `import_throughput_perf_test` | — |
| B-I3 | Longest UI-isolate synchronous slice during import | <= 50 ms | gap probe in perf tests | frame gaps |
| B-I4 | DB commits per import | <= pages + 2 | executor wrapper in perf test | — |
| B-I5 | Newest transactions visible on Dashboard after permission grant | <= 5 s (10k inbox) | — | device |
| B-I6 | Derived rebuild after import completes (10k) | one run, <= 30 s on device, started <= 2 s after import end | `derived_reads_perf_test` (timing), `derived_reads_service_test` (one trailing run) | device |
| B-M1 | Idle PSS, no model loaded | <= 250 MB | — | `dumpsys meminfo` (T-115) |
| B-M2 | PSS after navigation tour | <= 300 MB | — | same |
| B-M3 | Import peak PSS over idle | <= +100 MB, back to <= +30 MB within 60 s | — | same |
| B-M4 | Model loaded/idle release | measure and record first (ADR 0009 RAM gate stays); release within 60 s idle | — | T-115 |
| B-T1 | Required CI wall time | <= 6 min, each shard <= 5 min | `tool/ci/test_durations.py` | CI |
| B-A1 | Touch targets | every interactive control >= 48x48 dp (`docs/design-system.md:20`) | `androidTapTargetGuideline` audit | TalkBack/Switch pass |
| B-A2 | Semantics | every interactive control labeled; focus order = visual order | `labeledTapTargetGuideline` + custom check | TalkBack on six flows |
| B-A3 | Contrast | text >= 4.5:1 (>= 3:1 large text/graphics), light and dark | `textContrastGuideline` | spot check |
| B-A4 | Large text | no overflow/clipping at text scale 1.0, 1.3, 2.0 on 360x640, 411x891, landscape | viewport matrix audit | display size + font max |
| B-A5 | Reduced motion | all repeating animations stop (e.g. `BloomSkeleton`) | widget test | system setting |
| B-A6 | Import progress announced | live region, <= 1 announcement per 10 s | banner widget test | TalkBack |

Image/SVG note: `assets/icons` is 1.4 MB and fonts 1.0 MB (`du`); T-115 must
record decode cost on the startup path; no network image fetching exists
(ADR 0002).

## Constraints and invariants

- ADR 0011: derived reads and totals stay deterministic SQL; throttling never
  serves a stale final value (trailing edge is mandatory and tested).
- ADR 0002 / privacy: traces, logs and reports carry timings and counts only;
  no SMS text, amounts, senders or merchant names.
- Device measurements use an isolated test install; never clear or downgrade
  the owner's app (T-194 rules).
- Tests are never weakened or skipped; characterization asserts are flipped by
  the fixing task, not removed.
- Subtasks touch <= 3 production files; T-203, T-208 and T-210 files are
  disjoint within a parallel group (verified in each brief's group table).
  Cross-task file overlaps are serialized by `Depends`:
  `sms_backfill.dart` (T-203e then T-208f), `database.dart` (T-208c then
  T-208i), `transactions_providers.dart`/`transactions_screen.dart` (T-203f,
  T-203g6, then T-208k).

## Data model and ADR needs

None required. `idx_transactions_updated_at` and a partial Activity index are
created idempotently in `beforeOpen` like the existing lower() indexes; record
them in `docs/schema.md` (T-208c) and prove fresh-install vs upgraded index
parity. Conditional ADRs (numbers assigned by the orchestrator): isolate
parsing (T-208g), WAL (only if profiled need).

## Risks

| Risk | Mitigation |
|---|---|
| `invalidateSelf` may still report `isReloading` | Widget test in T-203c; fall back to `whenStable` at consumers |
| Partial index unused because Drift binds flags as `?` | T-208b/c verify plan; use literal predicates in repository query |
| Throttle hides a final update | Trailing edge + flush-on-done tests; acceptance compares to SQL |
| Bundling tests changes isolation | Gate on measured load share; compare test counts; keep standalone list |
| Host ceilings flaky on shared runners | p50 of >= 15 runs, device budget as ceiling, plan tests are the primary guard |
| Device numbers unavailable (phone disconnected) | Budgets stay `proposed`/advisory; gate does not block on guesses |
| `HomeShell`/`sms_backfill.dart` edit conflicts | Serialized `Depends` listed above |

## Rollout and flags

All UI changes are unflagged presentation changes behind tests. Throttle is
inert when no import runs. Startup trims (T-208i) ship individually and are
reverted by file. No feature-flag key is added; if one is needed for
`importStreamThrottle`, use `AppConstants` defaults, not a stored flag.

## Open owner questions

None blocking. Non-blocking: (1) accept the proposed numbers after the first
calibration run; (2) whether to show interim insights during a very long import
(current plan: derived reads update once, at the end).

## Subtask table

Parallel groups: tasks with the same letter inside one parent touch disjoint
files.

| ID | Title | Size | Model | Depends | Group |
|---|---|---|---|---|---|
| T-203a | Shared AsyncValue and database-gate helpers | S | Sonnet | — | A |
| T-203b | Import-aware stream throttle | S | Sonnet | — | A |
| T-203d | Derived reads: maxWait + trailing guarantee | M | Sonnet | — | A |
| T-203e | Import progress model and banner | M | Sonnet | — | A |
| T-203c | Dashboard no-skeleton refresh | M | Sonnet | a, b | B |
| T-203f | Activity keys, new-rows pill | M | Sonnet | a, b | B |
| T-203g2 | Settings `.when` (3 screens) | S | Haiku | a | B |
| T-203g2b | Settings root `.when` | S | Haiku | a | B |
| T-203g3a | Unparsed-SMS dev screen + providers | S | Haiku | a | B |
| T-203g3b | Flags + shadow metrics screens | S | Haiku | a | B |
| T-203g4 | Insights/Trends `.when` | S | Haiku | a | B |
| T-203g5a | Review + SMS-status `.when` | S | Haiku | a | B |
| T-203g5b | Recurring gates | S | Haiku | a | B |
| T-203g6 | Transactions-folder gates, detail, throttle | M | Sonnet | a, b, f | C |
| T-203h | No-flicker acceptance test | M | Sonnet | c, f, g* | D |
| T-203i | Before/after import report | S | Sonnet | h, T-208e | E |
| T-208a | Synthetic 50k ledger + EXPLAIN helper | M | Sonnet | — | A |
| T-208e | Import throughput benchmark | M | Sonnet | — | A |
| T-208h | Startup phase trace | S | Sonnet | — | A |
| T-208l | Device measurement kit | M | Sonnet | — | A |
| T-208b | Query-plan assertions | M | Sonnet | a | B |
| T-208d | Host latency + derived-reads benchmarks | M | Sonnet | a | B |
| T-208j1 | Rebuild-count/virtualisation tests | M | Sonnet | a | B |
| T-208c | Add demanded indexes | M | Sonnet | b | C |
| T-208f | Import hot-path improvements | M | Sonnet | e, T-203e | C |
| T-208g | Isolate-parsing decision note | S | Sonnet | f | D |
| T-208i | Startup path trims | M | Sonnet | h, c | D |
| T-208j2 | Device frame-timing integration test | M | Sonnet | a, T-203c/f, c | D |
| T-208k | Flatten Activity list (conditional) | M | Sonnet | T-203f, T-164b, j1 | D |
| T-210a | Duration ranking tool + tags | S | Haiku | — | A |
| T-210c1 | Hazard scanner | S | Haiku | — | A |
| T-210d | Shared test helpers + test config | M | Sonnet | — | A |
| T-210b | CI timing workflow | S | Haiku | a | B |
| T-210g1 | Tag migration tests | S | Haiku | a | B |
| T-210c2..c5 | Fix hazards per test folder | S each | Haiku | c1, d, b | C |
| T-210e | Folder bundles (conditional) | M | Sonnet | a, b, d | C |
| T-210f | Duration-balanced shard planner | M | Sonnet | a, b | C |
| T-210g2 | Tag slow files | S | Haiku | b, g1 | D |
| T-210h | Concurrency guidance in dev doc | S | Haiku | b, f | D |
| T-171a | CI shards (cross-reference) | M | Sonnet | T-210f, T-210h | after T-210 |
| T-171b1 | Acceptance-budget document | S | Haiku | — | A |
| T-171b2a | A11y guideline harness | M | Sonnet | — | A |
| T-171b2b | A11y audits: Dashboard, Activity | M | Sonnet | b2a | B |
| T-171b2c | A11y audits: other screens | M | Sonnet | b2a | B |
| T-171b3 | Budgets JSON + evidence checker | M | Sonnet | b1, T-208l | B |
| T-171b4 | Wire gate into release procedure | S | Haiku | b3, b2b, b2c | C |
