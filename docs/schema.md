# Schema

Schema source of truth is PLAN.md section 6 plus the Drift definitions under
`lib/data/db/tables/`.

Implemented in schema version 1:

- `transactions`: normalized transaction storage with indexes on `ts`,
  `merchant_id`, `category_id`, `ref_id`, and `status`.
- `raw_sms`: source SMS retention rows with processed state and purge deadline.
- `merchants`: canonical merchant rows with optional category hints and
  embeddings.
- `merchant_aliases`: seed, learned, and user aliases pointing at merchants.
- `categories`: category taxonomy rows, including parent links and spending
  flags.
- `rules`: user-taught hard mappings that can set category and description.
- `feedback`: training/correction records for category, merchant, and
  description edits.

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
