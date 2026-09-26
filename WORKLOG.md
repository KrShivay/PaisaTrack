# Current Handoff

## 2026-09-26 — Smart assistance planning and documentation cleanup

- Added the smart transaction assistance plan, T-177a–g briefs, proposed ADR
  0011, grounded-AI report and T-178a–d briefs. New feature work stays Backlog;
  no smart-assistance/AI implementation was made.
- Added ARCHICTURE.md as a navigation entry; retained docs/architecture.md as
  canonical. Updated roadmap, assistant/privacy/status notes and task/archive
  indexes; removed completed task prose and duplicate/model-specific queues.
  Short historical pointers retain commit a429994f; uncertain T-133/T-143 work
  remains open. T-140 integration gaps are explicitly owned by T-177.
- Three Luna high agents wrote/reviewed the report, pruned task records and
  independently reviewed plan and existing inset code. Fixed documentation
  gaps around immutable evidence versus corrections, assistant eligibility
  parity, and expected versus settled events.
- User requested a commit of all workspace changes, including pre-existing
  T-176 bottom-inset code. Only added code cleanup was removal of one unused
  test import. T-176 remains In Progress pending real-device acceptance.
- Verification: analyzer clean; focused inset/navigation tests 15/15 passed.
  Full Flutter suite 761/761 passed; changed-document links, unique board IDs,
  four board headings, three-entry handoff and whitespace checks passed.
  GitNexus refreshed; all-scope diff: 154 symbols, 2 expected content-padding
  processes, medium risk, no partial/truncated diff response. Index process
  enumeration is bounded, so this is not proof of exhaustive path coverage.
  Independent code review found no actionable inset regressions; real-device
  navigation/keyboard verification remains open.

## 2026-09-04 — PV-02 completeness/exclusions + stale exclusion test fix

- **PV-02 completeness (second half):** `DashboardAggregateSnapshot` now reports
  `excludedDebitTotal`/`excludedDebitCount` (settled spending debit removed by
  self-transfer or analytics-excluded flags for the period).
  `dashboardExclusionsProvider` projects it, and `BloomExclusionsNote` under the
  metric pills shows "₹X across N transfers & excluded items not counted in
  spending" (only on successful data with a non-zero amount). Repo + widget
  tests added. PV-02 is now implemented end to end (In Review).
- **Stale test fix (was pre-existing on main):** rewrote
  `exclusion_explanation_test.dart` to match shipped T-158d behaviour — an
  unflagged credit-card bill is counted and shows no exclusion banner; only
  flag-driven exclusion (owned transfer / analytics-excluded) is disclosed. The
  two tests previously asserted the removed merchant-pattern heuristics.
- Verified: `flutter analyze --no-pub` clean; full `flutter test` all green.

## 2026-09-04 — PV-02 truthful dashboard aggregates + review fixes

- **PV-02 (loading/error half):** The ~10 dashboard/insights aggregate-derived
  providers (`monthDirectionTotals`, `monthNet`, `dailyAverageSpend`,
  `safeToday`, `runway`, `projectedMonthEnd`, `monthOverMonthSpend`,
  `categoryBreakdown`, `topMerchants`, `sixMonthTrend`) now project
  `dashboardAggregateProvider` as `AsyncValue` and no longer fall back to the
  bounded 100-row `transactionListProvider`. Hero ring, budget card,
  top-categories, and the four insights sections render distinct loading/error
  states (skeleton / inline error). Removed `_countsAsSpending` (weaker than the
  SQL `FinancialEligibility` contract; it omitted `lifecycle_state='settled'`).
  Completeness/exclusion disclosure remains open on PV-02.
- **Trend timezone:** `_loadTrend` no longer uses SQLite `'localtime'`; it
  buckets with an explicit `DashboardQueryWindow.timeZoneOffset` threaded from
  `FinancialCalendar`, so month grouping honours the same calendar as the rest
  of analytics and is deterministic under an injected offset.
- **Sender blacklist:** added a "Block a sender" control + dialog in Settings —
  `pausedSenders` was enforced/displayed/removable but had no add path.
- **Docs:** refreshed `product-status.md` (status date; stale BloomCategoryTile
  fallback-glyph claim); updated PV-02 scope note in `TASKS.md`.
- Verified: `flutter analyze --no-pub` clean; full `flutter test` **732 passed,
  2 failed** — both failures (`exclusion_explanation_test.dart`) are
  **pre-existing on `main`** (they assert the CC-bill exclusion behaviour that
  T-158d intentionally removed), unrelated to this change. `detect_changes`:
  50 symbols / 4 processes, all expected.
