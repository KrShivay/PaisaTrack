# Architecture

PaisaTrack is organized as a local-first pipeline:

1. Native Android SMS capture filters and forwards candidate messages.
2. Dart capture code parses SMS into the normalized transaction record.
3. Intelligence enrichers resolve merchants, categories, recurring status, and insights.
4. Riverpod owns the app database lifetime through `appDatabaseProvider`,
   which opens encrypted SQLite with the Android Keystore-backed passphrase
   provider and can be overridden with an in-memory database in tests.
5. Repositories persist records in encrypted SQLite.
6. Experience screens read only normalized/enriched records.

Runtime SMS access is gated by `SmsPermissionGate` (platform channel
`com.paisatrack/sms_permissions`), surfaced through `smsPermissionControllerProvider`
and the onboarding screen. Denial is non-fatal: the app stays usable and explains
the degraded (no automatic capture) state rather than blocking.

Raw SMS bodies are temporary capture inputs and must not appear in release logs,
network payloads, or unencrypted exports.
