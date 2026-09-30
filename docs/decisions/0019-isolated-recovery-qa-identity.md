# ADR 0019: Isolated identity for physical recovery QA

Status: Accepted for the T-179a physical QA harness

## Context

The existing recovery device rehearsal calls `debugResetForTests()` and clears
generation keys. Running it under the owner package could erase the database
key used by the installed production app. A clean package alone is insufficient
because ordinary first-run startup creates a new key instead of showing the
lost-key recovery screen.

## Decision

Run T-179a physical recovery checks only in an explicitly enabled debug build
whose Android application ID is `com.paisatrack.recoveryqa`. The ordinary debug
and release identities and the production release build commands remain
unchanged. The QA-only manifest removes SMS permissions and the incoming SMS
receiver. It cannot request inbox access or receive new-message broadcasts.

Before Flutter starts, a QA-only `Application` checks the runtime package name,
generated application ID, debug build type, and QA build flag. Before any
provider, file, or Keystore operation, the Dart entrypoint and integration test
also require a QA-only native identity RPC to return those exact values. A
missing method, channel, or mismatch aborts the run. Recovery tests may reset
only keys in this distinct QA package after the identity checks and after
confirming its key registry is empty.

The physical scenario creates an encrypted SQLCipher database and `.ptrack`
backup using synthetic sentinel records and a dedicated test passphrase. It
keeps the database file while clearing only the QA package's legacy key, then
cold-launches the ordinary production `main()` path in the QA APK. The actual
`PaisaTrackApp` provider must route to `KeyLossScreen`; the backup is selected
through Android's Storage Access Framework and restored through the production
recovery service. A fresh process then reopens the restored database and checks
the synthetic sentinels. The legacy encrypted file family is compared
byte-for-byte. The harness also compares a SHA-256 digest of the synthetic
replacement legacy passphrase value before and after restore. This digest does
not attest Android Keystore alias or wrapped-preference continuity. Secret
values are never logged.

The debug-only APK and host phases are implemented and compile-checked. The
physical startup, real SAF selection, and cold-process verification remain
unrun while no device is connected; see the [T-179a QA report](../reports/T-179a-isolated-recovery-qa-2026-10-01.md).

## Consequences

This adds no database schema, production recovery behavior, release signing,
SMS scanning, or production APK packaging changes. The physical test proves
only the synthetic QA package path; it does not modify or validate the owner's
database or Keystore state. `debugResetForTests()` remains forbidden against
the production application ID.
