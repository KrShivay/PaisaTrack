# Current Handoff

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

## 2026-08-07 — T-143b sequence and adversarial fixtures complete

- Added ordered two-message fixtures and expected event graphs for auth→settle,
  debit→reversal, expense→refund, reminder→fulfilment, and bank+wallet echo.
  Added sanitized extraction-bait fixtures whose plausible numbers must remain
  non-amounts. The support export exposes both shapes without changing legacy
  single-message loading.
- Verification: analyzer clean; fixture-loader suite **5/5**; all fixture
  provenance is `device` and no raw personal identifiers are committed.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
