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

**Phase 1 (Capture MVP): complete — exit PASS (2026-07-07).** Delivered:
SMS permissions + onboarding (T-020), Kotlin receiver + sender filter (T-021),
live platform-channel ingestion (T-022), one-time 3-month inbox backfill
(T-023), real template registries for IndusInd/SBI/Paytm Payments Bank/Axis
with 136 sanitized real fixtures (T-024), paired bank+wallet duplicate
suppression (T-025), transactions list + dashboard + unparsed dev screen
(T-026, T-028), and a dark-first design system implemented in
`lib/core/theme/` (T-029, [docs/design-system.md](docs/design-system.md)).

Exit evidence (T-034, WORKLOG "PHASE P1 EXIT: PASS"): on-device parsed
transactions reconciled against real bank statements via
`scripts/reconcile_statement.py` — **94.4% statement coverage (388/411 rows)**
in the backfill window against the >=90% criterion, 381 exact-ref matches,
zero amount/direction contradictions. Known gap: NEFT/IMPS/ACH-credit SMS
shapes are not yet templated (T-047).

**Phase 2 (Usable Tracker): queue groomed.** T-035 (dedup/counterparty schema
ADR) through T-046 (exit review) are on [TASKS.md](TASKS.md). Intelligence is
on-device only with free components — no cloud inference path exists
(ADR 0002, [docs/decisions/0002-no-cloud-services.md](docs/decisions/0002-no-cloud-services.md)).

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
