# Current Handoff

## 2026-10-02 — T-188 Trends inbox (closed)

- Trends now has an inbox built only from fresh T-178a claims, deduplicated
  by kind + scope + calendar period (a repeated crossing updates the item;
  a new period creates one). States new/seen/moved/cleared persist in
  `model_meta` (`trends_inbox_v1`, no schema change) through transactions on
  a per-database serial queue; Clear all keeps `insights.dismissed` in step
  with Undo via UndoController; items that stop qualifying are hidden (state
  kept for dedupe/undo); items become seen when the user leaves Trends or
  backgrounds the app; the nav pill shows a Material badge with one
  announced count; retention is the current plus 3 previous periods;
  corrupt state is backed up and logged. `trendsInboxEnabledProvider=false`
  restores the plain feed. Spec: docs/specs/trends-inbox.md.
- Impact: final scan CRITICAL (shared ModelMeta/insights paths). Verified:
  analyzer clean, full suite 1083/1083, insights/intelligence/shell/data
  305/305 under America/New_York. Two review rounds (lost updates, stale
  numbers rendering, period-change flicker, badge scaling). Follow-up nit:
  after background → resume on Trends, items that turn new are marked seen
  only on the next leave. The T-164e closure entry is in Git history.

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
