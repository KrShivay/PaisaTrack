# ADR 0008: Bounded encrypted backup envelopes

Status: Accepted

Date: 2026-08-02

## Context

The encrypted backup service previously read every table row, retained all raw
SMS rows in the archive, accepted any Argon2id parameter tuple inside a broad
numeric range, and read a selected file completely before checking its size.
That made hostile or unexpectedly large exports a memory and privacy risk.

## Decision

Keep archive versions 1–3 and the existing JSON/AES-GCM envelope for import
compatibility, but enforce resource limits before expensive work. New
user-facing document exports use an additive binary streaming envelope
(protocol version 2):

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

The streaming envelope has a fixed 60 KiB plaintext chunk ceiling so each
authenticated record stays below the Android document gateway's 64 KiB
platform-channel ceiling. Each record uses a unique nonce derived from the
random base nonce and chunk index. AES-GCM associated data binds the exact
header, record kind, chunk index, and plaintext length. A final authenticated
manifest binds the data-chunk count and plaintext/ciphertext lengths; a
truncated or reordered file therefore cannot be accepted.

The plaintext archive stream is newline-delimited: a header, one table-row
record per line, and a footer containing per-table and total row counts. Rows
are paged from Drift during export and restored inside one database
transaction during import. The existing `exportBytes`/`importBytes` methods
remain bounded compatibility helpers for legacy callers; Settings uses the
session-based document gateway.

The Android Storage Access Framework exposes begin/write/finish and
begin/read/close sessions. Sessions transfer at most 64 KiB per call, close on
cancellation or engine detachment, and use stable content-free error codes.
Picker dismissal returns a non-success result; a destination is only reported
complete after the authenticated final manifest is written.

## Consequences

Oversized, unsupported, truncated, or cancelled archives fail closed without
replacing current database contents. Active raw SMS remains available for
source restoration, while expired source bodies cannot be extended by backup
retention. Transient export/import memory is bounded to one row/page, one
authenticated chunk, and the existing ciphertext ceiling. Physical SAF
acceptance on API 26+ devices remains release evidence tracked separately
from this code task.
