# Current Handoff

## 2026-08-07 — T-143c2 shadow diff computation complete

- Added a pure comparator for normalized production and shadow snapshots. It
  deterministically reports gained/lost records, amount deltas, and label
  disagreements, with stable source ordering and no database writes.
- Verification: analyzer clean; shadow/migration/diff focused suite **4/4**;
  full Flutter suite **663 tests** with the known unrelated
  `exclusion_explanation_test.dart` failure (expected 500, actual 5500).

## 2026-08-07 — T-143c1 shadow storage and runner complete

- Added schema v16 `shadow_transactions` storage and an isolated runner for
  normalized candidate outcomes. It records parsed, unparsed, and error rows
  idempotently without copying raw message bodies or touching production
  transactions.
- Verification: analyzer clean; shadow runner and v16 migration suite **2/2**;
  full Flutter suite **661 tests** with the known unrelated
  `exclusion_explanation_test.dart` failure (expected 500, actual 5500).

## 2026-08-07 — T-143a feature flags complete

- Seeded the local `feature_flags` table idempotently from typed defaults,
  preserving existing overrides. Added a typed developer editor for all 19
  flags, linked from Settings, with reactive edits and per-row/all reset.
- Verification: analyzer clean; focused flag suite **9/9**; full Flutter suite
  **659 tests** with the known unrelated `exclusion_explanation_test.dart`
  failure (expected 500, actual 5500). Edits persist through the reactive
  provider without an app restart.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
