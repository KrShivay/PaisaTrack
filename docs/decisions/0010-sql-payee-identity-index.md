# ADR 0010 — SQL payee identity index

Status: accepted for T-117 (2026-08-02)

## Context

Payee labels currently watch every eligible transaction, group the complete
history in Dart, and apply search and the unlabeled filter after materializing
the full list. That makes the Settings surface grow linearly with transaction
history and gives it no stable paging contract.

Unresolved identities use `MerchantResolver.normalizeAlias`: uppercase text
with every character outside `[A-Z0-9]` removed. SQLite has no equivalent
portable regular-expression function, so grouping directly on raw text would
change identity semantics.

## Decision

Add the derived `payee_evidence` table in schema v15. Each row stores a
transaction id, evidence type (`merchant_raw` or `counterparty_vpa`), the
normalized key used for grouping, and the original trimmed display value. It
is an index, not new user data: the source fields remain authoritative and the
index is rebuilt during migration and after encrypted backup restore.

The ingestion and correction write paths replace the two derived evidence rows
for a transaction. Manual transactions without merchant/VPA evidence create no
rows. The table has transaction and normalized-key indexes and a composite key
of transaction id plus evidence type.

Payee queries run in SQL. The first query returns only a keyset page of
identities, ordered by `display_name ASC, identity_key ASC`; a second query
loads aliases only for those page keys. Search matches the display name or
original aliases, and `unlabeled` means a missing or blank user label. Deleted
and duplicate-linked transactions are excluded in SQL. A page reads `limit +
1` identities to derive `hasMore` without offset paging.

Duplicate suggestions remain read-only. They are explainable merchant-cluster
suggestions and never merge aliases or merchants until the user confirms a
separate action.

## Consequences

- Payee Settings no longer materializes the complete transaction history for
  aggregation, filtering, or a page.
- Schema upgrades and restores pay a one-time derived-index rebuild cost;
  source transactions and user labels remain recoverable without the index.
- Leading-wildcard substring search still scans the eligible identity page;
  full-text search is deferred until realistic device measurements justify it.
- Any future write path that changes merchant/VPA evidence must update the
  derived index or explicitly rebuild it.
