# Current Handoff

## 2026-08-07 — T-153c end state, provider persistence, progress bar complete

- Skipping all items now shows "N skipped — review them?" instead of Inbox Zero.
  Skip state moved to `ReviewViewState` (survives widget disposal). Added
  `_SortProgressBar` (resolved/skipped/remaining segments) below header counter.
- Verification: analyzer clean; review focused suite **20/20**; commit ebf62cd.

## 2026-08-07 — T-153b back navigation complete

- Added `_goBack()` method and back-arrow button to the Sort card action row.
  Swipe-right now moves the cursor back instead of confirming. Back at cursor 0
  is a no-op. Drag stamp updated from "KEEP" to "BACK".
- Verification: analyzer clean; review focused suite **17/17**; commit a211935.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
