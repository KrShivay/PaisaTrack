# Current Handoff

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

## 2026-09-29 — T-186 transaction detail keyboard layout

- The transaction detail Scaffold now lets its containing sheet own keyboard
  insets, avoiding a second body resize when Note receives focus. The Note/Save
  header wraps at large text sizes. No schema or shared modal-helper change.
- Added synthetic geometry coverage for both modal and full-screen presentations
  at 1.0×, 1.5×, and 2.0× text, plus a keyboard-open Save Note tap and
  save/reopen coverage. No phone or personal data was accessed.
- Validation: focused keyboard/detail tests 17/17; full Flutter suite 838/838;
  `flutter analyze --no-pub`, formatting, and `git diff --check` clean. GitNexus
  pre-edit impact: TransactionDetailScreen HIGH (40 impacted symbols, 3 flows);
  showBloomModalSheet MEDIUM (10 symbols). Final detect-changes: 13 symbols in
  4 files, MEDIUM risk, with three affected test flows and no production flow.
  Independent review passed. Physical-device keyboard QA was not run; synthetic
  geometry coverage is the acceptance evidence for this UI-only change.

## 2026-09-29 — T-191 linked encrypted backup restore

- Fixed restore ordering for transaction links, duplicate transaction links,
  and category parent links in legacy JSON and chunked v3 archives. Restores
  preserve counterparties, expected events, and T-185 dispositions; malformed
  nullable link values fail closed instead of silently dropping relationships.
  Failed legacy and chunked restores leave the existing database unchanged.
- Added synthetic round-trip, `PRAGMA foreign_key_check`, malformed archive,
  rollback, and old-v3 compatibility coverage. No phone data or live archives
  were accessed.
- Validation: focused backup/recovery suites 36/36; full Flutter suite 831/831;
  `flutter analyze --no-pub`, formatting, and diff checks clean. Independent
  review passed. GitNexus detect-changes reports 8 files, 31 symbols, 10 flows,
  HIGH risk; full output. Changes are ready for commit and fast-forward push.
