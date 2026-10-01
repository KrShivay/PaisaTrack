# Current Handoff

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

## 2026-10-02 — T-178a a2 eligibility parity

- The settled-spending rule was restated by hand in five engines. One Drift
  builder on `FinancialEligibility` now serves insights, anomalies, burn-rate,
  recurring, assistant and dashboard exclusions, with a SQL/Drift/row parity
  test. Recurring detection is settled-only (a pending ₹649 event previously
  produced a false price-creep insight). Assistant net matches the dashboard
  contract (old: ₹270, contract: ₹350) and mixed-currency answers keep every
  currency.
- Impact: RecurringDetector/AnomalyDetector/InsightsEngine/BurnRateForecaster/
  DashboardRepository HIGH. Verified: analyzer clean, full suite 991/991,
  intelligence/data/dashboard 258/258 under TZ=UTC and America/New_York.
  Independent review approved; its follow-ups (same-currency guard on
  comparison scalars, shared `_loadTotals` fragment) are folded into a3. The
  6,000-row recurring timing test is flaky under machine load (failed once at
  5.39s, passed in isolation runs).
- The 2026-10-01 T-164e date-slice entry is in Git history.
