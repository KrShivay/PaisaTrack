# Current Handoff

## 2026-08-07 — T-153b back navigation complete

- Added `_goBack()` method and back-arrow button to the Sort card action row.
  Swipe-right now moves the cursor back instead of confirming. Back at cursor 0
  is a no-op. Drag stamp updated from "KEEP" to "BACK".
- Verification: analyzer clean; review focused suite **17/17**; commit a211935.

## 2026-08-07 — T-153a ordered queue + cursor complete

- Replaced `_skippedIds` filter with a stable `_stableQueue` + mutable `_cursor`.
  Skip advances the cursor without removing items; confirmed/recategorised items
  are removed with undo re-insertion. Deleted the dead `_currentIndex = 0` field.
- Verification: analyzer clean; review focused suite **15/15** pass; commit 635e63d.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
