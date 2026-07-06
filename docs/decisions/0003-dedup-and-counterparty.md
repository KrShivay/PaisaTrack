# ADR 0003: Explicit Duplicate Links and a Counterparty VPA Column

## Status

Accepted (2026-07-07, approved by @human) — implementation is T-036.

## Context

Two shortcuts from Phase 1 (T-025) are now load-bearing and about to be built
on by Phase 2 (detail screen, categorizer, category manager):

1. **Duplicate suppression overloads `is_deleted`.** When
   `DuplicateSuppressor` detects a cross-source echo (bank SMS + wallet SMS
   for one payment), `SmsIngestor` stores the new row with `isDeleted: true`.
   The flag now means two unrelated things — "user deleted this" (future
   Phase 2 behavior) and "system suppressed this as a duplicate" — which are
   impossible to distinguish, audit, or undo separately. A wrong suppression
   is silently unrecoverable from the UI.
2. **`counterparty_vpa` is squeezed into `merchant_raw`.** The normalized
   record (PLAN §6.2) carries `counterparty_vpa`, but the `transactions`
   table has no column for it, so ingestion falls back
   `merchantRaw ?? counterpartyVpa`. Merchant resolution (Phase 3) and P2P
   rule matching (`match_type='counterparty'`, Phase 2 T-039/T-040) need
   VPA and merchant text as separate signals; the fallback destroys that
   distinction. The T-034 reconciliation also showed VPA-shaped messages are
   how the *other linked account* manifests — a clean column enables
   account-scoped filtering later.

## Decision

Schema v2 (Drift migration), implemented in T-036:

1. Add `duplicate_of_txn_id TEXT NULL REFERENCES transactions(id)` to
   `transactions`, with an index. Semantics: non-null ⇒ this row is a
   cross-source echo of the referenced row. `DuplicateSuppressor` outcomes
   write this link and NO LONGER touch `is_deleted`.
2. `is_deleted` reverts to meaning user deletion only (soft delete from the
   Phase 2 detail screen).
3. Add `counterparty_vpa TEXT NULL` to `transactions`. Ingestion writes
   `merchant_raw` and `counterparty_vpa` independently; the
   `merchantRaw ?? counterpartyVpa` fallback is removed. List display name
   falls back at *query/presentation* time (merchant → VPA), not at write
   time, so stored data stays faithful to the SMS.
4. List and aggregate queries exclude rows where `duplicate_of_txn_id IS NOT
   NULL OR is_deleted = 1`. The dev screen gains a "Suppressed duplicates"
   view (primary row + echo side by side) so wrong suppressions are visible;
   un-suppressing (clearing the link) is a dev action now, a user detail
   action later.

### Migration and backfill

- v1→v2 adds both nullable columns (no table rebuild needed) + index.
- Existing v1 rows with `is_deleted=1` can be echoes (T-025) or nothing else
  (no user delete exists yet in v1). Backfill: for each such row, re-run the
  duplicate match (same direction, amount within tolerance, ts within the
  10-minute window, ref/counterparty key) against non-deleted rows; on a
  unique match set `duplicate_of_txn_id` and clear `is_deleted`; if no match
  is found, leave `is_deleted=1` (conservative: hidden stays hidden) and log
  the count. Migration test seeds a v1 database containing a suppressed echo
  and asserts it converts to a link.
- `counterparty_vpa` backfill: none. v1 rows conflated the fields at write
  time; reconstructing per-row provenance is guesswork. New ingests populate
  it; raw SMS still inside the 30-day retention window MAY be re-parsed
  opportunistically in T-036 if cheap, otherwise skipped.

### Contract note

PLAN §6.2's normalized record already contains `counterparty_vpa`; this ADR
brings storage in line with the frozen contract rather than changing it. The
`duplicate_of_txn_id` column is storage-internal and does not alter the
parser contract.

## Consequences

- User deletion and system suppression become independent, auditable, and
  separately reversible; the detail screen (T-038) can safely implement soft
  delete without colliding with dedup.
- Rules and merchant resolution get an honest `counterparty_vpa` signal;
  P2P "always ask once" (PLAN §7.5) keys on VPA rather than merchant text.
- Queries must filter on two columns instead of one (helper in the
  repository layer keeps this in one place).
- One-time migration cost on upgrade; the echo backfill is bounded by the
  small number of v1 suppressed rows (4 in the developer's current DB).
- `TransactionJsonExporter` and `scripts/reconcile_statement.py` gain the
  `duplicate_of_txn_id` field (export schema addition is backward-compatible
  for the script, which ignores unknown keys).
