# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

This repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
The product and technical source of truth is [PLAN.md](PLAN.md).
Feature work must include matching tests and documentation; see
[docs/development.md](docs/development.md).

## Current Status

**Phase 0 (Foundation): complete.** All exit criteria are met and reviewed —
`flutter test` green in CI, encrypted Drift DB creates + migrates (host tests
skip SQLCipher when the VM lacks it; Android migration device-tested on
motorola_edge_50_pro), and the fixture runner asserts parser output. Android
`minSdk` is pinned to API 26 (PLAN §2).

**Phase 1 (Capture MVP): in progress.** Delivered and reviewed (PASS):

- SMS runtime permissions + onboarding flow (graceful denial handling) — T-020.
- Kotlin SMS `BroadcastReceiver` + `SmsFilter` allowlist (rejects OTP/promo/
personal senders), with JUnit tests — T-021.
- Live SMS platform channel → Dart ingestion bootstrap, raw SMS persistence,
and transaction write-on-parse-success flow (idempotent by SMS id) — T-022.
- Historical SMS inbox backfill on first permission grant: reads the last three
months on-device, filters and ingests in non-blocking chunks, and runs once via
a persisted marker so cold starts never re-scan or duplicate — T-023.

Verification: repo-local `flutter analyze` is clean; `flutter test` is green
(36 passed / 1 host SQLCipher skip), including the capture contract and the
backfill idempotency test (re-running inserts no duplicate rows); Android JUnit
via `:app:testDebugUnitTest` is green with the live channel bridge and inbox
reader compiled. Next: real bank template registries + sanitized fixtures
(T-024). Remaining Phase 1 work is tracked in [TASKS.md](TASKS.md) (T-024
through T-027).

## Local Setup

This repo currently uses a repo-local Flutter SDK at `.tooling/flutter`.
If your shell does not have Flutter on `PATH`, run commands through that SDK:

```sh
.tooling/flutter/bin/flutter pub get
.tooling/flutter/bin/flutter test
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter build apk --debug
```

Android native (Kotlin) unit tests run through Gradle:

```sh
cd android && ./gradlew :app:testDebugUnitTest
```

No raw SMS data should be committed. Use sanitized fixtures under
`test/fixtures/sms/<bank>/`.
