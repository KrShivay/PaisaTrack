# Schema

The executable source of truth is the Drift schema under
`lib/data/db/tables/` and `lib/data/db/database.dart`.

## Current schema

- `transactions`: normalized rows, source evidence, status, soft deletion,
  duplicate links, payment-source links, owned-transfer links, and analytics
  exclusion state.
- `raw_sms`: retained source messages and processing state.
- `merchants` / `merchant_aliases`: canonical identity, user labels, and aliases.
- `payee_evidence`: derived, rebuildable normalized merchant/VPA evidence used
  by SQL payee aggregation and keyset search; original transaction fields stay
  authoritative.
- `payment_sources`: masked accounts/cards/wallets, nicknames, institution,
  ownership, active state, and analytics inclusion.
- `categories`, `rules`, `feedback`: taxonomy and learning inputs.
- `recurring_series`, `insights`, `model_meta`: local intelligence state.
- `baselines`: anomaly/forecast state plus the current global monthly-budget and
  merchant-cap prototype. This reuse is transitional; T-098 requires a
  dedicated per-category/per-month budget model.

The database is SQLCipher-encrypted. Android Keystore protects the generated
database passphrase. Original merchant text, VPA, references, and source metadata
must remain distinguishable from user-authored labels.

## Planned additive areas

Exact tables are chosen during task design, but future migrations will need to
represent:

- transaction relationships for refunds/reimbursements (T-100);
- expected recurring events separate from settled transactions (T-101);
- statement imports, source-row fingerprints, and reconciliation decisions
  (T-102);
- monthly category budgets (T-098).

Each migration must preserve existing rows, include upgrade tests from the
previous version, and update encrypted backup/import coverage where relevant.

Amounts and balances currently use Drift `real()`/Dart `double`. This is a
known financial-integrity limitation; T-130 plans an additive migration to
integer paise rather than extending floating-point use into new money tables.

Schema v6 is a repair migration: it backfills NULLs and rescales millisecond
datetimes in `payment_sources` rows created by early v5 builds (which crashed
the transactions and accounts screens through the generated force-unwrapping
row mapper) and recreates the source-inference trigger to write second-based
timestamps. It never clears app data. Regression fixture:
`test/data/db/app_database_v6_payment_source_repair_test.dart`.

Schema v7 repairs another legacy v5/v6 table shape that omitted newer
`payment_sources` columns such as `institution` and `nickname`. It adds every
expected non-key column defensively, keeps existing account rows, reruns the v6
value/timestamp normalization, and recreates the trigger. Regression fixture:
`test/data/db/app_database_v7_payment_source_shape_repair_test.dart`.

Schema v8 adds an optional `evidence_json` column to `transactions` table (T-131a)
to store verifying span evidence (`FieldEvidence`) linking extracted amounts,
directions, and timestamps back to verbatim source text. Existing rows read back
with null evidence. Regression fixture:
`test/data/db/app_database_v8_migration_test.dart`.

Schema v9 adds `lifecycle_state` (default `'settled'`), `lifecycle_reason`, and `message_kind`
columns to `transactions` table (T-132a) and creates an index `idx_transactions_lifecycle_state`.
Existing rows backfill `lifecycle_state` to `'settled'`. Regression fixture:
`test/data/db/app_database_v9_migration_test.dart`.

Schema v10 adds `financial_events` (id, event_key unique, key_basis, kind, net_amount_paise, currency, opened_at, closed_at, state, confidence) and `transaction_links` (id, from_txn_id, to_txn_id, link_type, confidence, basis, created_by, created_at) tables (T-134a). Monetary amounts in new tables use integer paise. Regression fixture:
`test/data/db/app_database_v10_migration_test.dart`.

Schema v11 adds `counterparties` (id, kind, identity_key unique, display_name, inferred_name, psp_family, merchant_id, first_seen, last_seen, txn_count) table (T-136a). Regression fixture:
`test/data/db/app_database_v11_migration_test.dart`.

Schema v12 adds `expected_events` (id, source, origin_sms_id, series_id, counterparty_id, label, expected_amount_paise, amount_low_paise, amount_high_paise, expected_date, date_window_days default 3, cadence, state, fulfilled_txn_id, confidence, dedup_key) table (T-138a). Regression fixture:
`test/data/db/app_database_v12_migration_test.dart`.

Schema v13 adds `feature_flags` (key primary key, value, updated_at) table (T-143a) to store dynamic behavioral thresholds and flags with `AppConstants` acting as static fallbacks. Regression fixture:
`test/data/db/app_database_v13_migration_test.dart`.

Schema v15 adds `payee_evidence` for T-117. It stores one derived row per
non-empty merchant/VPA evidence field and indexes transaction and normalized
identity lookups. Existing transactions are backfilled without changing their
source fields; the index is also rebuilt after an encrypted archive restore.
