# Current Handoff

## 2026-10-02 — UNDO-1 undo toast above every route

- Physical T-193 QA showed the 10-second undo toast was hosted only by
  HomeShell and hidden behind Transaction Detail. One shared root builder
  now hosts it in `MaterialApp.builder` with a route observer: Home keeps
  pill clearance; other routes sit above the safe area/keyboard; dialogs
  hide it (like SnackBars) and it returns if still live; bottom sheets keep
  it visible. Verified: analyzer clean, full suite 1060/1060; an app-level
  test fails if the wiring is removed. Two review rounds (post-frame flag
  race, untested wiring). Physical recheck rides on the next release install.
  The T-178a a4 entry is in Git history (`bc870ec`).

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
