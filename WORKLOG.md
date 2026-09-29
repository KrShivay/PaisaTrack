# Current Handoff

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

## 2026-09-29 — T-184 verified SLICE SMS capture

- Added exact `SLICE` native sender admission. Synthetic native tests cover
  live and inbox filtering, plus rejection when `SLICE` appears only in an
  unknown sender's body signature.
- The generic parser now extracts the sample payee before the parenthesized UPI
  reference and uses a valid `on d-MMM-yy` date only when it occurs within the
  same short transaction clause after the payment verb. Unrelated footer dates
  and invalid calendar days retain the SMS receive time. Footer-only text is
  not parsed as a transaction. No schema, cloud, raw-SMS logging, or retention
  changes; T-162b remains separate. Synthetic data only; no device access.
- Validation: focused parser suite 16/16; full Flutter suite 821/821;
  `flutter analyze --no-pub`, Dart formatting, and `git diff --check` clean.
  Android `SmsFilterTest` and app Kotlin compilation passed with temporary
  Gradle 9.1 distribution after verifying its SHA-256. GitNexus impact before
  edits: SmsFilter.isAllowed LOW (2 direct callers; 1 flow), parser MEDIUM
  (8 direct callers; 2 test processes); SmsFilter class was UNKNOWN but text
  search confirmed its native paths. Change analysis: 16 symbols across 6 files,
  7 affected processes, HIGH risk; flows include parser/cascade ingestion,
  shadow pipeline, and test entrypoints. Independent review pending; no
  commit/push.
