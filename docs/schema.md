# Schema

The executable source of truth is the Drift schema under
`lib/data/db/tables/` and `lib/data/db/database.dart`.

## Current schema

- `transactions`: normalized rows, source evidence, status, soft deletion,
  duplicate links, payment-source links, owned-transfer links, and analytics
  exclusion state.
- `raw_sms`: retained source messages and processing state.
- `merchants` / `merchant_aliases`: canonical identity, user labels, and aliases.
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
