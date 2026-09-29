# Current Handoff

## 2026-09-29 — T-167a primary-screen error and retry states

- Activity now distinguishes first-load errors from true empty state, preserves
  already loaded rows on later stream errors, including page-two failures before
  their first row, and offers Retry without leaking a future error from the
  load-more callback. Explicit retry resets its cursor snapshot before
  subscribing to the first page again. Trends aggregate failures now have a
  Retry action instead of the nonfunctional “Pull to refresh” instruction.
- Added actual-screen widget coverage for Activity empty vs initial error and
  retry recovery, loaded-data preservation and retry recovery, and Trends
  aggregate failure/recovery. No database schema or device changes.
- Validation: focused Activity/Trends/controller tests 13/13; full Flutter
  suite 870/870; `flutter analyze --no-pub`, formatting, and `git diff --check`
  clean. GitNexus detect-changes: 4 files, 5 symbols, 0 processes, LOW risk.
  Independent review pending.

## 2026-09-29 — T-176 global bottom-inset acceptance

- Added Trends and Settings final-content geometry checks at 24dp gesture and
  48dp three-button insets. Existing inset/detail tests cover category FAB and
  Manual Entry keyboard behavior, plus transaction detail in modal and
  full-screen sheets with keyboard and 1x–2x text. No production gap was
  demonstrated, so the shared inset contract is unchanged.
- The 320×568/2× layout repro also produced horizontal overflows in the
  HomeShell navigation pill (`home_shell.dart:250`), Activity header
  (`transactions_screen.dart:220`), and Trends header
  (`insights_screen.dart:73`); these are tracked by T-167c. Not transactions,
  nested destination/action-sheet routes, Ask keyboard behavior, compact /
  landscape large-text combinations, and physical-device QA remain open. The
  phone was disconnected.
- Validation: focused inset/detail/Ask suites 24/24; full Flutter suite
  866/866; `flutter analyze --no-pub`, formatting, and `git diff --check` clean.
  GitNexus detect-changes: 3 files, 17 symbols, one affected flow, MEDIUM risk
  (the geometry test exercises `ForTabContent`); no production code changed.
  Independent review pending.

## 2026-09-29 — T-187 source-currency fidelity (review passed)

- Carries explicit source currency and symbol through parsers, schema v18,
  recurring series/status memory, expected-event reconciliation, analytics,
  Ask responses, transaction UI, exports, and both backup formats. USD and
  unknown-dollar amounts stay separate; legacy rows without evidence remain
  unknown. INR-only budget math is labelled, and the dashboard exposes separate
  foreign/unknown subtotals. Trends now labels its INR-only charts and lists
  other currency buckets separately. Ask category breakdowns use stable
  label/currency ordering instead of ranking nominal totals across currencies.
  No FX conversion or phone data access.
- Regression coverage includes adjacent prefix/suffix parsing, duplicate
  account/amount digits, bare-dollar vs USD event matching, historical v1 and
  chunked-v3 backup defaults, migration compatibility, per-currency analytics,
  source-aware UI/export, and 2× text-scale layout. Unknown reminders reconcile
  only with unknown debits sharing VPA/amount/date constraints.
- Validation: full Flutter suite 1,030/1,030; `flutter analyze --no-pub`,
  changed-file Dart format check, and `git diff --check` clean. GitNexus
  compare with main: 89 files, 143 symbols, 47 affected flows, CRITICAL risk;
  post-review working-tree detect-changes: 9 files, 8 symbols, 0 flows, LOW
  risk. Impact warnings were surfaced before edits. Independent review passed
  on `a5e2e61`; main was fast-forwarded and pushed to the same revision.
