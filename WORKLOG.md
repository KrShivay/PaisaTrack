# Current Handoff

## 2026-08-08 — T-154a sort card opens detail sheet complete

- `_SortCard` is now a tap target. Tapping opens `TransactionDetailScreen`
  as a Bloom full-screen sheet. On dismiss, the matching `_stableQueue` entry
  is refreshed from the provider without resetting the cursor.
- Verification: analyzer clean; review focused suite **21/21**; commit cc5df62.

## 2026-08-07 — T-153c end state, provider persistence, progress bar complete

- Skipping all items now shows "N skipped — review them?" instead of Inbox Zero.
  Skip state moved to `ReviewViewState` (survives widget disposal). Added
  `_SortProgressBar` (resolved/skipped/remaining segments) below header counter.
- Verification: analyzer clean; review focused suite **20/20**; commit ebf62cd.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
