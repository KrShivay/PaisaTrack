# Current Handoff

## 2026-09-29 — T-187 source-currency fidelity (review-ready)

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
  risk. Impact warnings were surfaced before edits. Independent review pending.

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

## 2026-09-29 — T-185 durable SMS disposition

- Added a local `not_transaction` disposition keyed by provider SMS ID and a
  dedicated transaction flag. Replay suppression covers live, batch, history,
  and catch-up ingestion. The detail action has a Settings restore list that
  survives restart and raw-SMS expiry; restoration re-links expected events
  and rebuilds payee evidence. Mark/restore awaits recurring, anomaly, forecast,
  and insight refresh so stale derived state is not shown after completion.
  Paused/cancelled/muted recurring status is preserved by stable series identity
  across detector ID changes. Dispositions round-trip through both encrypted
  archive formats; legacy and chunked v3 archives with the optional table and
  transaction flag absent restore defaults safely. No message content is
  retained and no phone, archive, or live user data was accessed.
- Added synthetic coverage for mark/undo after raw expiry, ingestion replay,
  expected-event and payee-evidence restoration, recurring status, payment
  source counts, and old legacy/chunked archives. Fixed migration ordering so
  payee-evidence backfill runs only after all added columns exist.
- The refresh remains awaited so derived rows are not presented as current
  before recomputation. A temporary synthetic 5,001-row/1,500-day benchmark
  completed mark plus derived refresh in 140 ms on the local in-memory test DB;
  device and disk timings may differ. The temporary benchmark file was removed.
- Validation: focused disposition/payment-source/backup tests 27/27; targeted
  legacy migration tests 7/7; full Flutter suite 826/826; `flutter analyze`,
  Dart format on changed files, and `git diff --check` clean. GitNexus
  detect-changes: 41 files, 124 symbols, 9 affected processes, HIGH risk; full
  output with no truncation. The independent final review accepted the patch.
  HIGH/CRITICAL impact warnings were surfaced before edits. Branch is ready for
  commit and fast-forward integration; no device or archive access.
