# Current Handoff

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

## 2026-10-01 — v2012 owner-phone install and Ask portrait check

- Built and independently reviewed the signed ARM64 `0.1.3+2012` artifact
  from release commit `9f966992f8665c4f7fea72882af1270cb34b3c3b`. Android app
  and keystore Gradle unit tests passed: 31 app tests and 10 keystore tests,
  zero failures. Flutter focused 29/29, full 954/954, analyzer, and formatting
  evidence is from unchanged source at `3d5f310`; the version-only bump did not
  rerun that suite. Artifact metadata and install evidence:
  [v2012 owner-phone report](docs/reports/release-v2012-owner-phone-install-2026-10-01.md).
- The candidate installed via `adb install -r`; package code 4012, installed
  base hash, and production signer matched, while `firstInstallTime` remained
  `2026-09-26 22:20:54`. Ask opened via the production pill. The focused empty
  composer stayed 59–62 px above the real IME at 1×, 1.5×, and 2× portrait;
  at 2× a safe swipe exposed one suggestion control. Close returned Home.
  Font/rotation settings were restored. No messages or transaction edits were
  made; no private records were inspected. Landscape and broader T-176/T-167c
  acceptance remain open. The exact artifact was published to `apk-downloads`
  in commit `79614386e4f5271c5ccefc67eca66368642fb7ae`; only the APK file
  changed.
