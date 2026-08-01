# ADR 0008: Bounded encrypted backup envelopes

Status: Accepted

Date: 2026-08-02

## Context

The encrypted backup service previously read every table row, retained all raw
SMS rows in the archive, accepted any Argon2id parameter tuple inside a broad
numeric range, and read a selected file completely before checking its size.
That made hostile or unexpectedly large exports a memory and privacy risk.

## Decision

Keep archive versions 1–3 and the existing JSON/AES-GCM envelope, but enforce
resource limits before expensive work:

- 32 MiB maximum encrypted file/envelope;
- 16 MiB maximum decoded ciphertext and decrypted archive JSON;
- 50,000 rows maximum per table and 200,000 rows maximum across an archive;
- only the shipped production Argon2id profile is accepted:
  19,456 KiB memory, parallelism 1, iterations 2, and 32-byte output;
- export retains a raw SMS row only while `purge_after` is strictly after the
  captured export time; restore also skips expired rows.

File length is checked before `readAsBytes`, and ciphertext/row counts are
checked before Argon2 derivation or database mutation. Limits fail with stable,
content-free `EncryptedBackupException` messages. Additional KDF profiles must
ship with an explicit compatibility fixture before they are accepted.

## Consequences

Oversized or unsupported archives fail closed without replacing current
database contents. Active raw SMS remains available for source restoration,
while expired source bodies cannot be extended by backup retention. The JSON
archive is still materialized in memory; chunked authenticated streaming,
progress reporting, and document-picker compatibility are the remaining T-127
slice.
