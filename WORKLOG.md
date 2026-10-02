# Current Handoff

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

## 2026-10-02 — T-193 QA fixture and repair/onboarding fixes

- Owner data has no repair-eligible row (all currency-unknown rows are from
  2023; raw SMS is kept 30 days), so a synthetic fixture for the isolated QA
  package was added (prepare + fresh-process verify; procedure in the T-193
  QA report). Building it exposed that `Rs.500`-style amounts were never
  repairable; the service now accepts dotted currency tokens and rejects a
  token that precedes another number. "Continue without SMS" was in-memory
  only; it is now a persisted `onboardingCompleted` setting with one source
  of truth, Home stays mounted during permission refreshes, and load errors
  route to onboarding.
- Impact: `SourceCurrencyRepairService` and `AppSettingsController`
  CRITICAL, `AppSettings` HIGH. Verified: analyzer clean, full suite green
  (1007/1007 after rebase onto a2),
  QA targets compile to `com.paisatrack.recoveryqa`. Three review rounds.
  Physical preview/apply/undo remains pending. The T-179a closure entry is in
  Git history (`10092b0`).
