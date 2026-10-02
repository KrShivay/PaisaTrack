# Current Handoff

## 2026-10-02 — T-178a a4 typed evidence-linked claims (T-178a closed)

- Insights now carry a typed claim in the existing payload (window,
  metrics, evidence ids with a digest over all evidence and eligibility
  fields, per-claim coverage by exclusion reason). Only claims that pass the
  validator and a read-time freshness recompute on the same
  `FinancialCalendar` render, through a fixed observed-only renderer; "Why?"
  opens Activity filtered to the evidence rows. Free-text narrative,
  generic default text and advice copy were removed; anomaly and forecast
  cards stay hidden until T-178b gives them claims. Refunds remain gross
  (no production refund linking; T-100). Trends can be empty when no claim
  qualifies; this is documented.
- Impact: `InsightsEngine`/`TransactionRepository` CRITICAL,
  `TransactionsScreen` HIGH. Verified: analyzer clean, full suite 1051/1051
  (twice), intelligence/insights/dashboard/transactions 326/326 under UTC,
  New York and Kolkata. Three review rounds (>50-row claims never rendering,
  hash missing eligibility fields, leaked drift watches, write/read calendar
  mismatch). The recurring scaling test now uses warm-up + best-of-3.
- T-193 physical preview/apply/undo is staged on the phone's QA package and
  waits for the phone to be unlocked; see TASKS.

## 2026-10-02 — T-164e detail/export/manual-entry slice

- Transaction detail re-implemented the clock/month formatting; it now reuses
  `format.dart` (output unchanged, pinned by tests). The release and debug
  CSV exporters split dates by hand twice; one calendar-aware formatter now
  serves both and appends a `UTC Offset` column written as `UTC+05:30` so
  spreadsheets do not read it as a formula or time. Manual entry dropped the
  time of day when a date was picked; it now keeps it and converts local
  fields through `FinancialCalendar` with an injected clock in tests.
- Verified: analyzer clean, full suite 1038/1038; transactions/core/dev
  suites green under TZ=UTC and America/New_York. One review round (CSV
  offset formula bug, dev exporter calendar injection, clock flake in test).
  The a2 entry is in Git history (`99c1397`).

## 2026-10-02 — T-178a a3 derived-read freshness

- Insights, anomalies, forecasts and recurring series were refreshed only
  nightly or after not-transaction changes, so edits left Trends stale for up
  to a day, and anomaly baselines froze partial periods and ignored zero-spend
  periods. `DerivedReadsService` now rebuilds them after every relevant write
  (debounced, single-flight, startup reconciliation, backfill suspension)
  and the nightly job shares its stages. Anomaly baselines are rebuilt from
  completed zero-filled periods. User-paused recurring series keep their
  status across rebuilds and amount drift.
- Impact: `SmsIngestor`/`AppDatabase` CRITICAL; detectors, insights engine,
  `SmsDispositionRepository` HIGH. Verified: analyzer clean, full suite
  1031/1031, intelligence/data 231/231 under TZ=UTC and America/New_York.
  Three review rounds (startup blanking, double trailing runs, freshness
  race, lost wakeup across suspension, same-merchant series collision all
  fixed with fail-before tests). Also restores the AGENTS.md/CLAUDE.md
  GitNexus block that `f6bdc6c` overwrote with a worktree index name.
- The a1 entry is in Git history (`0e6d8c4`).
