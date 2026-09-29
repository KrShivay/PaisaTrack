# Current Handoff

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

## 2026-09-28 — T-183 live SMS lifecycle guard

- Wired one local cue classifier into live capture, history import, and
  incremental catch-up. Non-transactional and unknown messages stop before
  extraction; failed, pending, and reversal records retain explicit lifecycle
  state and review status. The classifier preserves settled debit/credit with
  trailing balance context. A promotion footer yields to a specific account/card
  movement or an amount-led paid/spent/purchase phrase tied to a payee; generic
  reward copy such as “Rs 100 spent via UPI” remains a promotion. Model direction
  must agree with an explicit SMS debit/credit cue. A bare “purchase of … for
  Rs …” may disambiguate a balance message but does not override promotion
  cues because the wording is ambiguous. Unknown classification fails closed.
- Bumped the retained-SMS parser contract to version 2 so failures are retried
  under the new classifier by default. Added actual-provider adversarial and
  model-unavailable tests, plus history and catch-up provider tests. No sender
  filter, database schema, cloud, or raw-SMS retention changes. T-184 sender
  admission and T-185 durable “Not a transaction” remain separate backlog work.
- Validation: focused capture/lifecycle/history suite 57/57; full Flutter suite
  818/818; `flutter analyze --no-pub`, Dart format check, and `git diff --check`
  clean. GitNexus `detect-changes --scope all`: 12 files, 42 symbols, 13
  processes, HIGH risk. Refreshed index reports unrelated whole-flow truncation
  and cross-language unresolved property edges; earlier CRITICAL/UNKNOWN
  warning was surfaced. Independent review pending. No phone, archive, APK, or
  live SMS access.
