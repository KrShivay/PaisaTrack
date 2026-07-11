# Privacy

PaisaTrack is local-first:

- Raw SMS and transactions never leave the device by default.
- Historical inbox backfill (T-023) reads `Telephony.Sms.Inbox` on-device only; the
  filtered messages flow straight into the encrypted local store and message bodies
  are never logged, even on error paths.
- Raw SMS retention is capped by the purge policy in PLAN.md.
- There is no cloud inference path (ADR 0002). No network call ever carries user
  data; the only permitted network use is the optional one-time download of
  open-weight model files. All intelligence — parsing, classification,
  embeddings, LLM extraction — runs on-device with free components.
- Release builds must not log raw SMS bodies.
- Voluntary SMS fixture donation starts only from the unparsed-message dev
  screen. Names, account/reference digits, and balances are masked on-device;
  the complete `device`-provenance JSON fixture is shown without truncation,
  and it is copied only after the user approves that exact preview. Cancelling
  leaves the fixture on-device.
- Developer tooling: the dev screen's transactions-JSON export is compiled out
  of release builds (`kDebugMode`). It warns that normalized financial data is
  plaintext before Android's system document picker lets the developer choose
  a destination. Bank statements and reconciliation reports used for Phase 1
  verification live in the gitignored `BankStatement/` folder and are never
  committed; the same applies to copied on-device transaction exports.
- Settings `Delete everything` closes the local database, deletes SQLCipher
  database files, clears Android Keystore-wrapped passphrase material, resets
  app-private settings, and recreates the database with bundled categories only.
- User-facing backup export/import writes `paisatrack_export.ptrack`, a
  passphrase-encrypted JSON archive using Argon2id and AES-GCM. Plaintext domain
  JSON is kept in memory only and is never written as a temp file. Android's
  Storage Access Framework writes/reads only the document the user selects and
  requires no broad storage permission.
- The Android manifest gained the INTERNET permission for exactly one purpose:
  downloading pinned, integrity-checked open-weight model files (ADR 0007 now;
  ADR 0008's Phase 4 LLM later). The download request carries no user data and
  inference code paths never open a network connection; the permission's scope
  is documented inline in the manifest and enforced by review.
