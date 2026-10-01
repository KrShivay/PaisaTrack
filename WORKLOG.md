# Current Handoff

## 2026-10-01 — T-178a a1 fair comparison windows

- Every month-over-month comparison compared a partial current month with the
  full previous month (owner phone on 1 Oct: "97% lower spend than last
  month"). `FinancialCalendar.comparablePrior`, `throughToday` and
  `elapsedDays` now define one same-elapsed-days window used by insights
  `category_delta` (window stored in the payload; legacy rows keep old copy),
  the dashboard/Trends card (honest label when the prior month is clamped),
  and assistant comparisons; a `clockProvider` keeps provider and widget in
  agreement. Six-month trend bounds moved onto `FinancialCalendar`.
- Impact: `FinancialCalendar` CRITICAL, `DashboardPeriod`/`InsightsEngine`/
  `IntentValidator`/`AnswerRenderer` HIGH. Verified: analyzer clean, full
  suite 986/986 (IST host), intelligence/dashboard/insights/core 296/296
  under both `TZ=UTC` and `TZ=America/New_York`. Two independent review
  rounds; the first blocked a wall-clock-dependent widget test (fails on the
  last day of a month), fixed with the injected clock. The v2012 install
  evidence remains in its report and the T-193 release note.

## 2026-10-01 — T-164e SMS body-date, picker, and insights month-key slice

- ADB listed no device, so T-179a physical recovery stayed blocked; this
  non-device P0 slice was taken instead. Date-only SMS body values were
  stored as UTC-midnight instants (IST showed an invented 5:30 am; negative
  offsets moved the day). `FinancialCalendar.resolveDateOnly` now keeps
  `receivedAt` for same/future local days and uses local midnight for earlier
  days, for both template and generic parsing. One `financialCalendarProvider`
  feeds live capture, history import, and catch-up. The dashboard range picker
  seeds local dates clamped to today. Trends and the Dashboard insight card
  queried the previous month in IST; they now use the period calendar's month
  key. Stored rows are unchanged; body-dated SMS more than 10 minutes apart no
  longer auto-pair as duplicates (tests document it).
- GitNexus pre-edit impact: `parseDate`, `SmsIngestor`, `ParserCascade`,
  `TemplateMatcher` and `FinancialCalendar` CRITICAL, `FieldNormalizer` HIGH;
  provider UNKNOWNs corroborated by text search. Verification on the IST host:
  `flutter analyze --no-pub` clean, full suite 971/971, capture/fixtures/
  insights/core subset 319/319 under `TZ=UTC` and 321/321 under
  `TZ=America/New_York` (with the picker test), format and diff checks clean.
  Two independent reviews: the first required pinning host-zone-dependent
  fixture tests; the second approved, with calendar-plumbing DRY fixes
  applied after it. A pre-existing six-month-trend failure under New York
  time on unmodified main is recorded in TASKS (T-164e/T-178a). No phone, APK,
  or schema change.

## 2026-10-01 — T-179a physical recovery acceptance (closed)

- With the phone on wireless ADB, the isolated `com.paisatrack.recoveryqa`
  debug build (code 2012, debug signer, no SMS permissions) ran prepare, cold
  launch to the production KeyLossScreen, real SAF selection of the synthetic
  archive, restore, and fresh-process verify: legacy family and preserved copy
  byte-identical, archive and passphrase digests matched, sentinel rows,
  integrity and foreign keys ok. Flutter's install fallback uninstalls the
  built package on failure, so the APK identity was checked with `aapt2`
  before any device phase and all phases used `--no-uninstall`/`install -r`.
  The owner package stayed at 4012 with unchanged install timestamps; no
  owner data, key, backup or setting was touched. The verify marker compared
  hash maps by identity; `recoveryQaHashMapsEqual` fixes it (unit test 3/3)
  and the re-run reported true. Evidence:
  [T-179a report](docs/reports/T-179a-isolated-recovery-qa-2026-10-01.md).
  Keystore alias continuity remains unattested by design.
