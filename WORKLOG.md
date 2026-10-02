# Current Handoff

## 2026-10-02 — Release 0.1.4+2013 published

- Signed ARM64 APK from `7c1d1d0`: 56,947,112 bytes, SHA-256 `c22bac44…8ac4`,
  code 4013, production signer. Installed in place on the owner phone
  (firstInstallTime unchanged, installed hash matched), cold launch 550 ms
  with Home/Trends inbox rendering and no app fatal. Published on
  `apk-downloads` as `ad6bb48` (remote blob verified). Details in
  docs/release-signing.md. Next build: Home greeting copy should say "same
  days last month"; physical UNDO-1 and T-176/T-167c landscape/2× rechecks.
  The T-193 entry is in Git history (`385e056`).

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
