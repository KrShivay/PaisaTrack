# Current Handoff

## 2026-10-02 — T-193 physical acceptance (closed)

- On the owner phone, isolated QA package only: the synthetic `Rs.1,234.50`
  row offered the source-backed repair; preview was non-mutating; Apply
  showed `-₹1,234.50` and a fresh-process verifier confirmed `INR`/`₹`; on a
  fresh fixture, Apply then Undo restored both currency fields to null
  (fresh-process verified, preview available again). The launcher opened
  straight to Home, confirming persisted onboarding completion. Owner app
  untouched; QA package removed afterwards. `flutter test` cannot attach to
  the VM service over wireless ADB, so targets ran as installed debug APKs
  with logcat markers. Report: docs/reports/T-193-currency-repair-qa-2026-10-01.md.
- Defect found and filed as UNDO-1: the undo toast is hosted only by
  HomeShell and is hidden behind Transaction Detail. The T-164e
  detail/export entry is in Git history (`07c8ece`).

## 2026-10-02 — T-164e closed (filter dates on FinancialCalendar)

- `TransactionFilters.matches` compared device-local dates; it now uses the
  injected `FinancialCalendar` with half-open day bounds (inclusive end day),
  with 00:30/23:59 regressions under an offset that differs from the device.
  With the earlier slices (SMS body dates, picker, insights month key,
  detail/export/manual entry) every T-164e surface now follows one calendar
  contract; there is no importer yet, so docs/architecture.md records the
  contract a future importer must follow. Verified: analyzer clean, full
  suite green. The a3 entry is in Git history (`5fe9f85`).

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
