# Schema

Schema source of truth is PLAN.md section 6 plus the Drift definitions under
`lib/data/db/tables/`.

Implemented in schema version 3:

- `transactions`: normalized transaction storage with indexes on `ts`,
  `merchant_id`, `category_id`, `ref_id`, `status`, and `duplicate_of_txn_id`.
  `is_deleted` means user-initiated soft delete only; `duplicate_of_txn_id`
  (nullable, self-referencing) means this row is a cross-source echo of the
  referenced row (ADR 0003). `counterparty_vpa` is an independent signal from
  `merchant_raw`, written at parse time and never folded together.
- `raw_sms`: source SMS retention rows with processed state and purge deadline.
- `merchants`: canonical merchant rows with optional category hints and
  embeddings.
- `merchant_aliases`: seed, learned, and user aliases pointing at merchants.
- `categories`: category taxonomy rows, including parent links and spending
  flags.
- `rules`: user-taught hard mappings that can set category and description.
- `feedback`: training/correction records for category, merchant, and
  description edits.
- `recurring_series`: detected subscriptions, EMIs, bills, and income, indexed
  by `merchant_id` and `next_expected_date` for the recurring scanner/screen.
- `baselines`: keyed rolling mean, standard deviation, and sample count for
  anomaly detection.
- `model_meta`: key-value state for classifier weights, versions, policy
  thresholds, and the ADR 0005 template trust-ledger cache
  (`template_trust_ledger_v1`).
- `insights`: dismissable precomputed insight payloads, indexed by period.

`merchants.embedding` remains a nullable BLOB in v3. It is intentionally
unused until T-050 introduces the on-device embedder.

Migration log:

- 2026-07-05: Repository scaffold only. No database migrations implemented yet.
- 2026-07-05: Added Drift schema version 1 with encrypted SQLCipher opening
  path and migration test for `transactions`, `raw_sms`, `merchants`,
  `merchant_aliases`, `categories`, `rules`, and `feedback`.
- 2026-07-05: Added Android Keystore-backed database passphrase provider. The
  first app run generates a random SQLCipher passphrase, wraps it with an
  `AndroidKeyStore` AES-GCM key, and stores only encrypted bytes in app-private
  preferences. StrongBox is requested on supported Android devices, with normal
  Keystore fallback when StrongBox is unavailable.
- 2026-07-07: Schema v2 (ADR 0003, T-036). Added `transactions.counterparty_vpa`
  (nullable) and `transactions.duplicate_of_txn_id` (nullable, self-referencing
  `transactions.id`, indexed). `DuplicateSuppressor` now writes the link
  instead of overloading `is_deleted`; `is_deleted` reverts to user-delete-only
  semantics. List/dashboard queries exclude rows where `is_deleted = 1 OR
  duplicate_of_txn_id IS NOT NULL`. Migration backfill: for each v1 row with
  `is_deleted = 1`, re-runs the pairing rule (direction, amount tolerance,
  10-minute window, ref id or counterparty key) against the other rows; a
  unique match sets `duplicate_of_txn_id` and clears `is_deleted`, otherwise
  the row is left `is_deleted = 1` and logged. No backfill for
  `counterparty_vpa` (v1 rows conflated it into `merchant_raw` at write time;
  provenance is not reliably reconstructible) — only new ingests populate it.
- 2026-07-10: Schema v3 (T-048). Additive v2→v3 migration adds
  `recurring_series`, `baselines`, `model_meta`, and `insights`; it does not
  alter or rewrite existing rows. `insights.period`,
  `recurring_series.merchant_id`, and `recurring_series.next_expected_date`
  are indexed.

Encrypted backup archive:

- T-043 exports `paisatrack_export.ptrack`, an encrypted JSON archive. Version 1
  stores complete rows for categories, merchants, raw SMS, merchant aliases,
  transactions, rules, and feedback. The outer file contains Argon2id
  parameters plus AES-256-GCM nonce/MAC/ciphertext; plaintext table JSON stays
  in memory only.
