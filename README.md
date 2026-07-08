# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

The repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
[PLAN.md](PLAN.md) is the product and technical source of truth. Feature work
must include tests and documentation; see [docs/development.md](docs/development.md).

## Current Status

**Phase 0 (Foundation): complete.** The Flutter/Android scaffold, encrypted
Drift schema, Keystore-backed database passphrase, category seeds, fixture
harness, and CI guardrails are in place. Android `minSdk` is pinned to API 26.

**Phase 1 (Capture MVP): complete — exit PASS (2026-07-07).** Delivered SMS
permissions and onboarding, native SMS receiver/filtering, live platform-channel
ingestion, one-time three-month inbox backfill, real template registries for
IndusInd/SBI/Paytm Payments Bank/Axis, duplicate suppression, transaction list,
dashboard, unparsed-SMS dev screen, and the dark-first design system. Phase 1
exit evidence reconciled on-device parsed transactions against real bank
statements with **94.4% coverage (388/411 rows)** and zero amount/direction
contradictions.

**Phase 2 (Usable Tracker): in progress.** Schema v2, manual entry, transaction
detail/edit feedback, seed/rule categorization, category manager, settings, data
reset, and encrypted export/import have been implemented or prepared. Several
items still need the canonical Flutter analyze/test verification pass; see
[TASKS.md](TASKS.md) for exact state.

**Current focus.** Finish Phase 2 by verifying T-037/T-038/T-039, wiring
Decision policy v1 (T-040), building the ask-now notification flow (T-044), the
weekly review screen (T-045), and the Phase 2 exit review (T-046). T-047 added
IndusInd NEFT/ACH-credit templates and reports **99.03% statement coverage
(407/411 rows)** in the fixture/SMS-dump simulation; final Flutter fixture tests
and a fresh device export remain before it is marked Done.

Intelligence is on-device only with free components. No cloud inference path
exists; see [ADR 0002](docs/decisions/0002-no-cloud-services.md).

## Local Setup

The repo uses the repo-local Flutter SDK at `.tooling/flutter`:

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
