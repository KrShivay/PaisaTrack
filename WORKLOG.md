# Current Handoff

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

## 2026-08-07 — T-151a assistant sheet conformance complete

- Replaced the route-level `Scaffold`/`AppBar` with one custom assistant header:
  34px mascot, single title, emerald on-device subtitle, close affordance, and
  divider. The Ask orb now opens the existing full-height draggable sheet with
  a fixed `#0E0C1A` surface in both themes.
- Added a custom-header hook to the shared Bloom sheet scaffold so the assistant
  does not render duplicate title/close controls.
- Verification: analyzer clean; focused assistant, navigation, accessibility,
  and full-screen-sheet suite **20/20**; full Flutter suite retains the
  unrelated `exclusion_explanation_test.dart` baseline failure (expected 500,
  actual 5500).

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
