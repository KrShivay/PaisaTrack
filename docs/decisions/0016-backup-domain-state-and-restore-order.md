# ADR 0016: Preserve linked domain state in encrypted backups

**Status:** Accepted for T-191

## Context

Restore previously omitted relationship tables and deleted transactions before
their dependents. This could either violate SQLite foreign keys or leave the
restored ledger without transaction links, category hierarchy, counterparties,
or expected-payment state. Chunked archives also insert records in stream order,
so self-references can point to rows that have not been inserted yet.

## Decision

Encrypted archives include transaction links, counterparties, expected events,
category parent links, duplicate-transaction references, and the existing
`sms_dispositions` state. Restore clears dependent rows before parent rows and
then restores self-references after their rows exist. Chunked restore buffers
only the parent IDs needed for that second pass. Before the surrounding
transaction commits, restore runs `PRAGMA foreign_key_check` and fails the
whole restore on any violation.

New relationship tables remain optional when importing older v3 archives.
Missing optional rows restore as empty state; missing disposition rows and the
transaction `isNotTransaction` flag retain T-185's safe defaults. Existing
archive versions and encryption envelopes do not change.

## Privacy and rollback

Backup content remains in the user's passphrase-encrypted archive. Tests use
synthetic archive/database fixtures and never access a physical phone or live
financial data. Raw SMS continues to follow the existing expiry policy.
Reverting the restore fix leaves older archive formats supported and restores
the previous behavior; the source database remains protected by transactional
rollback on failed imports.
