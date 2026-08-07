# Current Handoff

## 2026-08-07 — T-143b sequence and adversarial fixtures complete

- Added ordered two-message fixtures and expected event graphs for auth→settle,
  debit→reversal, expense→refund, reminder→fulfilment, and bank+wallet echo.
  Added sanitized extraction-bait fixtures whose plausible numbers must remain
  non-amounts. The support export exposes both shapes without changing legacy
  single-message loading.
- Verification: analyzer clean; fixture-loader suite **5/5**; all fixture
  provenance is `device` and no raw personal identifiers are committed.

## 2026-08-07 — T-150c rotating composer chips complete

- Added a 30px horizontal chip row above the composer once a conversation has
  started. It shows three fixed-width catalogue questions at a time, sends a
  tapped question through the existing path, and rotates deterministically via
  the refresh control.
- Verification: analyzer clean; focused assistant/navigation suite **13/13**;
  full Flutter suite retains the unrelated `exclusion_explanation_test.dart`
  baseline failure (expected 500, actual 5500).

## 2026-08-07 — T-151c assistant composer styling complete

- Updated the composer to the Bloom handoff: 52px dark pill with `#2E2A4E`
  border, exact ellipsis placeholder, and a 40px emerald gradient send button
  with an ink-colored arrow.
- Verification: analyzer clean; focused assistant/navigation suite **13/13**;
  full Flutter suite retains the unrelated `exclusion_explanation_test.dart`
  baseline failure (expected 500, actual 5500).

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
