# Current Handoff

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

## 2026-10-01 — T-179a physical recovery acceptance (closed)

- With the phone on wireless ADB, the isolated `com.paisatrack.recoveryqa`
  debug build (code 2012, debug signer, no SMS permissions) ran prepare, cold
  launch to the production KeyLossScreen, real SAF selection of the synthetic
  archive, restore, and fresh-process verify: legacy family and preserved copy
  byte-identical, archive and passphrase digests matched, sentinel rows,
  integrity and foreign keys ok. Flutter's install fallback uninstalls the
  built package on failure, so the APK identity was checked with `aapt2`
  before any device phase and all phases used `--no-uninstall`/`install -r`.
  The owner package stayed at 4012 with unchanged install timestamps; no
  owner data, key, backup or setting was touched. The verify marker compared
  hash maps by identity; `recoveryQaHashMapsEqual` fixes it (unit test 3/3)
  and the re-run reported true. Evidence:
  [T-179a report](docs/reports/T-179a-isolated-recovery-qa-2026-10-01.md).
  Keystore alias continuity remains unattested by design.
