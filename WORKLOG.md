# Current Handoff

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

## 2026-10-01 — T-178a a1 fair comparison windows

- Every month-over-month comparison compared a partial current month with the
  full previous month (owner phone on 1 Oct: "97% lower spend than last
  month"). `FinancialCalendar.comparablePrior`, `throughToday` and
  `elapsedDays` now define one same-elapsed-days window used by insights
  `category_delta` (window stored in the payload; legacy rows keep old copy),
  the dashboard/Trends card (honest label when the prior month is clamped),
  and assistant comparisons; a `clockProvider` keeps provider and widget in
  agreement. Six-month trend bounds moved onto `FinancialCalendar`.
- Impact: `FinancialCalendar` CRITICAL, `DashboardPeriod`/`InsightsEngine`/
  `IntentValidator`/`AnswerRenderer` HIGH. Verified: analyzer clean, full
  suite 986/986 (IST host), intelligence/dashboard/insights/core 296/296
  under both `TZ=UTC` and `TZ=America/New_York`. Two independent review
  rounds; the first blocked a wall-clock-dependent widget test (fails on the
  last day of a month), fixed with the injected clock. The v2012 install
  evidence remains in its report and the T-193 release note.
