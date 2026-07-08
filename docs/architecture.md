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

All UI follows the binding conventions in [design-system.md](design-system.md);
themes and tokens live in `lib/core/theme/` (dark-first, light as an equal
derived variant). Settings owns theme selection, ask budget, feature-flag
readouts, and local data reset.

Runtime SMS access is gated by `SmsPermissionGate` (platform channel
`com.paisatrack/sms_permissions`), surfaced through `smsPermissionControllerProvider`
and the onboarding screen. Denial is non-fatal: the app stays usable and explains
the degraded (no automatic capture) state rather than blocking.

Live SMS delivery uses a separate EventChannel (`com.paisatrack/sms_events`).
Android forwards filter-approved `CapturedSms` payloads into that channel, and
Riverpod boots the Dart listener through `smsCaptureBootstrapProvider` only
after permission is granted and the encrypted database is ready.

## Capture pipeline (Phase 1, shipped)

1. `SmsFilter` (Kotlin) allowlists bank/UPI DLT senders and rejects OTP,
   promo, and personal messages before anything crosses to Dart.
2. Historical backfill (`SmsBackfiller`, one-time on first grant, window set
   by `AppConstants.smsBackfillMonths`) and live capture share the same
   `SmsIngestor` write path.
3. `ParserCascade` runs `TemplateMatcher` over the real bank registries in
   `assets/templates/{axisbk,indusind,paytmb,sbi}.json` (loaded via
   `parserCascadeProvider`). Parse success writes a transaction; failure
   leaves the raw SMS `processed=false`, visible on the dev Unparsed screen.
   No cloud parsing path exists (ADR 0002).
4. `DuplicateSuppressor` marks cross-source echoes (paired bank+wallet SMS)
   within a 10-minute window; suppressed rows stay stored for audit.
5. Raw SMS rows are purged after the retention window; transactions persist.

## Enrichment (Phase 2, in progress)

`Categorizer` (`lib/enrichment/`) runs the PLAN §7.4 ladder at ingest time,
steps 1 + 3 for now: user-taught rules (`RuleRepository`, match_types
`merchant` substring / `counterparty` exact-VPA, confidence 1.0, hit counts
maintained) → bundled seed keyword map (`assets/seed/category_seed.json`,
longest-key-first substring match, 0.8) → `other` at 0.3 (guaranteed to enter
the ask/batch flow once the decision policy lands, T-040). Both live capture
and backfill construct `SmsIngestor` with the categorizer
(`categorizerProvider`), and the outcome is recorded in the transaction's
`confidence_json` under `category` (`c`, `src`, optional `rule_id`). The
classifier (step 2) and on-device LLM (step 4) slot in during later phases.

## Verification tooling

`scripts/reconcile_statement.py` reconciles bank-statement XLSX exports
against SMS-parsed transactions (fixtures or an on-device JSON export via the
debug-only dev-screen button). Phase 1 exit was proven with it: 94.4%
statement coverage, zero contradictions (WORKLOG "PHASE P1 EXIT: PASS").
Statements and reports live in the gitignored `BankStatement/` folder.

Raw SMS bodies are temporary capture inputs and must not appear in release logs,
network payloads, or unencrypted exports. Settings `Delete everything` closes
the Riverpod database, deletes SQLCipher database sidecars, clears the Android
Keystore-wrapped passphrase via `com.paisatrack/database_passphrase`, resets
app-private settings, and reopens a database seeded only with bundled
categories.
