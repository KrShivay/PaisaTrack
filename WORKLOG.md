# Current Handoff

## 2026-09-27 — PV-02 aggregate parity and truthful dashboard scope

- Added a corpus-seeded SQL parity test that seeds all 20 current corpus rows and
  pins eligible spending/credit IDs, excluded IDs, totals, category totals, and
  trend totals. The corpus `long_history` descriptor says 125 rows but contains
  only two; no broader-history or performance claim is made.
- Added visible dashboard period, settled-spending and credit eligibility,
  known-exclusion, and local-record coverage explanations. Loading/error states
  do not present an exclusion amount as if aggregation succeeded.
- Kept the monthly budget action ahead of the detailed disclosure. Placed the
  disclosure after Recent so the lazy final transaction row remains reachable;
  geometry coverage verifies both it and the final disclosure line clear the
  floating navigation pill.
- Verified: focused dashboard/shell/corpus suite **16/16**; analyzer clean; full
  Flutter suite **764/764**, exit code 0; `git diff --check` clean. The initial
  full run caught a dashboard navigation geometry regression; the disclosure
  was moved after Recent and the final test verifies it clears the nav pill.
  GitNexus change map: 8 files / 14 indexed symbols, LOW risk, no affected
  processes. Flow inventory is bounded, so missing flows are not treated as
  proof of no impact.

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
