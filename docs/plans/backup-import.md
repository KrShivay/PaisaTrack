# Backup import and restore acceptance plan

Status: **Deferred; plan only.** This document does not authorize a restore or
claim physical acceptance. Import remains governed by [ADR 0008](../decisions/0008-bounded-encrypted-backups.md),
[ADR 0012](../decisions/0012-generation-based-database-recovery.md),
[ADR 0016](../decisions/0016-backup-domain-state-and-restore-order.md), and
[ADR 0019](../decisions/0019-isolated-recovery-qa-identity.md).

## Verified current behavior

- `EncryptedBackupService.importFromDocument` reads a bounded document session,
  routes chunked and legacy formats, and closes the session in `finally`
  ([source](../../lib/features/backup/encrypted_backup_service.dart#L292)).
- `KeyLossScreen._restore` calls `DatabaseRecoveryService.restoreFromDocument`,
  invalidates/reopens the database after success, and clears the passphrase
  controller in `finally` ([source](../../lib/features/recovery/key_loss_screen.dart#L35)).
- Archive limits, authenticated chunks, optional relationship tables, restore
  order and foreign-key checking are defined in ADR 0008/0016 and
  [architecture](../architecture.md#storage-and-privacy).
- T-179a's physical QA report records an isolated package restore run with
  synthetic sentinels on 2026-10-01. It explicitly does not attest Keystore
  alias or wrapped-preference continuity
  ([report](../reports/T-179a-isolated-recovery-qa-2026-10-01.md)).
- **Unverified:** broader physical matrix for cancellation, wrong passphrase,
  truncation, process interruption at activation boundaries and older archive
  versions on supported Android versions.

## Hard boundary

Physical restore on the owner's `com.paisatrack` identity is forbidden. Any
future device restore uses only the isolated `com.paisatrack.recoveryqa` debug
identity and preflight checks in ADR 0019/T-179a. Never ask for, copy, display,
log, or store the owner's backup passphrase. Never access
`~/Downloads/PaisaTrackBackups`. Use only a synthetic `.ptrack` archive and
synthetic test passphrase in QA identity storage. This deferred plan does not
schedule device work.

## Deferred acceptance matrix

| Area | Synthetic/host evidence before a device run | Isolated device evidence required later |
|---|---|---|
| Valid import | Legacy v1 JSON and chunked v2 fixture; sentinel transactions, payment sources, links, counterparties, category parents, expected events, dispositions; `PRAGMA integrity_check` and `foreign_key_check` | QA identity selects one synthetic archive through SAF, cold process reopens and verifies sentinel counts/hashes |
| Existing data preservation | Failure-injection tests before activation prove source DB family and active pointer unchanged | QA identity compares encrypted source-family hashes before/after failed restore |
| Passphrase/authentication failure | Wrong synthetic passphrase, tampered tag, truncated/reordered chunks, invalid header and oversized envelope fail closed | Observe stable content-free error; do not capture passphrase or screen text containing secret |
| Limits/cancellation | Boundary file/chunk/row limits, picker cancellation, read cancellation, session closure | QA picker cancellation and cancel during import leave active generation unchanged |
| Process death | Fault points before staging, during copy, before pointer commit, uncertain commit; startup selects only a valid active generation and keeps retryable staging state per ADR 0012 | Fresh QA process after each approved fault point; never reset production keys |
| Compatibility | Older v1/v3 archives missing optional relationship tables restore safe defaults; new archives restore optional tables | One synthetic oldest-supported fixture and one current fixture via QA package |
| Cleanup | Restore transaction rollback; retry and reset/delete cleanup tests | Remove synthetic archive from QA-only storage and preserve the QA identity audit record |

## Promotion gates

Before any acceptance task is promoted to Ready:

1. Define supported Android/API matrix and oldest archive version; owner reviews
   pass/fail cases and what constitutes a recoverable failure.
2. Confirm recovery writer/readers resolve active generation through the same
   selector and lock, including background workers.
3. Add/confirm synthetic tests for every matrix row, failure boundary,
   archive-format compatibility, backup linkage and reset/delete behavior.
4. Obtain a separate task authorization for isolated-device acceptance. Use the
   ADR 0019 QA build flags, verify QA identity before any file/Keystore work,
   and confirm QA key registry is empty before test reset.
5. Do not test from a personal backup or owner's Downloads. Do not move the
   passphrase through chat, logs or evidence. Owner enters only the synthetic
   test passphrase into the QA harness.

## Evidence and rollback

Future report must include QA application ID/build identity, device/API class,
APK hash, archive fixture ID/hash, phase result, row counts, SQL/FK integrity,
source-family hashes and generation outcome. Exclude passphrase, private files,
device serial and owner package data. Keep the existing active generation and
encrypted source family untouched. Any mismatch fails closed; retain the
previous generation and leave the recovery gate open for investigation.

## Readiness

Planning can be reviewed now. Physical acceptance remains Deferred pending an
owner-scheduled isolated QA run and review of its synthetic-only evidence. The
2026-10-01 T-179a report is existing evidence for its stated scenario only; it
does not close T-170b or all archive/import paths.
