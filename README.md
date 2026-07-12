# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

The repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
[PLAN.md](PLAN.md) is the product and technical source of truth. Feature work
must include tests and documentation; see [docs/development.md](docs/development.md).

## Current Status

Phase 4 now includes a grounded in-app assistant, validated on-device LLM
fallback for unmatched transaction SMS, and aggregate-only monthly narratives.
These model-backed paths are enabled for the Phase 4 release; model download is
still explicit, and deterministic parsing/insights work when it is absent.

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

**Phase 2 (Usable Tracker): build complete.** Schema v2, manual entry,
transaction detail/edit feedback, seed/rule categorization, category manager,
settings, data reset, encrypted export/import, Decision policy v1 ingest status
wiring, ask-now notifications (T-044), and the weekly review screen (T-045) are
all landed. Corrections from either surface flow through one write path
(`correctWithRule`): rule + feedback + status update in a single DB transaction.
The ask budget reads the Settings slider; credits only offer income-side
categories. See [TASKS.md](TASKS.md) for exact state.

**Phase 2 exit: PASS (2026-07-10, T-046).** All four PLAN §9 criteria verified
(daily-usable loop, ≤2 asks/day by construction, correction→rule→auto-label
traced end-to-end, encrypted export→wipe→import round-trip) plus on-device
sign-offs. T-047's IndusInd NEFT/ACH-credit templates report **99.03%
statement coverage (407/411 rows)** in the fixture/SMS-dump simulation.

**Current focus: Phase 2.5 — Parser Coverage.** Field reports showed users on
untemplated banks (Kotak, Central Bank) got zero parsed transactions. The
generic fallback parser (T-066, `docs/parser-generic-fallback.md`) now converts
such SMS into low-confidence, review-routed transactions; bank template packs
(T-067, fixtures pending) and on-device rejection-stage triage (T-069) follow.
Development runs on an automated two-agent handoff loop (ADR 0004). Phase 3
(on-device intelligence) is groomed behind it.

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

## build_install.sh

Run release:

```sh
./build_install.sh release
```

Specify a device when multiple devices are connected:

```sh
./build_install.sh debug ZD222KTYNC
```

For a clean rebuild, add this before flutter pub get:

```sh
flutter clean
```
