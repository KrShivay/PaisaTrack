# Current Handoff

## 2026-08-07 — T-153a ordered queue + cursor complete

- Replaced `_skippedIds` filter with a stable `_stableQueue` + mutable `_cursor`.
  Skip advances the cursor without removing items; confirmed/recategorised items
  are removed with undo re-insertion. Deleted the dead `_currentIndex = 0` field.
- Verification: analyzer clean; review focused suite **15/15** pass; commit 635e63d.

## 2026-08-07 — T-143c3 shadow metrics surface complete

- Added a local developer metrics screen for shadow/production counts and the
  four diff categories. The report copy action is explicit and exports counts
  only; no source ids or message bodies leave the screen.
- Verification: analyzer clean; shadow metrics/diff/runner focused suite **5/5**;
  full Flutter suite **665 tests** with the known unrelated
  `exclusion_explanation_test.dart` failure (expected 500, actual 5500).

## 2026-08-07 — T-143c2 shadow diff computation complete

- Added a pure comparator for normalized production and shadow snapshots. It
  deterministically reports gained/lost records, amount deltas, and label
  disagreements, with stable source ordering and no database writes.
- Verification: analyzer clean; shadow/migration/diff focused suite **4/4**;
  full Flutter suite **663 tests** with the known unrelated
  `exclusion_explanation_test.dart` failure (expected 500, actual 5500).

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
