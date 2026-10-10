# Privacy

PaisaTrack is local-first:

- Raw SMS and transactions never leave the device by default.
- Historical inbox import keyset-pages the full
  `Telephony.Sms.Inbox` on-device only. Filtered messages flow straight into the
  encrypted local store; page checkpoints contain only timestamp/id cursors,
  and message bodies are never logged, even on error paths. The explicit
  Settings re-import rescans locally and preserves user edits/deletions.
- After the versioned initial import, open/resume catch-up reads only messages
  through the first known SMS's page and one older recovery page. Live receiver
  and catch-up paths share the same on-device parser and encrypted store.
- Sent-time identity and optional exact receipt-hash compatibility are computed
  on-device. Alternate mappings and bounded per-run conflict evidence are
  transient; they add no backup fields, remote lookup or telemetry. Retained
  sender/body must match exactly before a stored alias is accepted. User edits,
  exclusions and existing transaction/source IDs remain authoritative.
- Source SMS provenance is kept ([ADR 0021](decisions/0021-retain-source-sms-provenance.md)):
  the SMS behind a transaction or a "Not a transaction" disposition stays in
  the encrypted local database for as long as that record exists. Any other
  raw SMS (unparsed, unreadable, never linked) is deleted 7 days after receipt
  (`AppConstants.rawSmsRetentionDays`).
- Encrypted backups include every linked source SMS plus unlinked SMS whose
  `purge_after` is still in the future; restore removes expired unlinked rows.
  Each kept SMS adds roughly 340 bytes to a backup. Backup files are capped at
  32 MiB, decoded ciphertext/plaintext at 16 MiB, and rows at 50,000 per table
  and 200,000 per archive. Settings transfers bounded authenticated chunks
  through the Android document picker; Drift rows are paged on export and
  restored transactionally on import. No plaintext archive temp file is
  created, and a cancelled or incomplete destination is never reported as a
  completed backup.
- Settings → "Restore SMS sources" re-reads the inbox on the device, through
  the same reader and permission as history import, to re-link source SMS
  that the earlier 30-day purge removed. It links only exact matches, never
  edits transactions, skips paused senders, and reports only counts.
- A user's “Not a transaction” correction persists the deterministic source SMS ID,
  transaction ID, disposition, and correction time in the encrypted local
  database and backup. The disposition itself stores no message body, sender,
  or receipt time; the source SMS it refers to is kept as provenance
  (ADR 0021). The correction remains reversible in Settings.
- The user-facing "Messages we couldn't read" surface reads only allowlisted
  failure reasons and expiry metadata. It reports retained counts without
  loading bodies, senders, or identifiers, and excludes rows past their expiry
  even before nightly cleanup runs. These unlinked rows expire after 7 days.
- There is no cloud inference path (ADR 0002). No network call ever carries user
  data; the only permitted network use is the optional one-time download of
  open-weight model files. All intelligence — parsing, classification,
  embeddings, LLM extraction — runs on-device with free components.
- Release builds must not log raw SMS bodies.
- Voluntary SMS fixture donation starts only from the unparsed-message dev
  screen. On-device, the sanitizer masks account/reference digits, balances,
  UPI/email handles (the local-part becomes `<VPA>`, keeping the non-personal
  PSP/domain), and personal names — titled ("Dear <name>"), untitled-leading
  ("<name> paid …"), and payee/counterparty ("paid to <name>") — while retaining
  the transaction amount, including large comma-less amounts. Name masking
  remains best-effort: it keys on Title-Case heuristics, so ALLCAPS or lowercase
  merchant/bank tokens are intentionally left intact and an unusually-cased name
  can still slip through. That residual risk is why the complete
  `device`-provenance JSON fixture is shown in full, without truncation, and is
  copied only after the user approves that exact preview. Cancelling leaves the
  fixture on-device.
- Developer tooling: the dev screen's transactions-JSON export is compiled out
  of release builds (`kDebugMode`). It warns that normalized financial data is
  plaintext before Android's system document picker lets the developer choose
  a destination. Real statements, reconciliation reports, and copied on-device
  exports are gitignored and must never be committed.
- Settings `Delete everything` currently closes the local database, deletes
  SQLCipher files, clears Android Keystore-wrapped passphrase material, resets
  Dart settings and SMS-import checkpoints, and recreates bundled categories.
  It does not yet clear native pending ask-answer preferences, posted
  notifications, or downloaded/partial model files. Until T-124 lands, the UI
  must not promise complete device erasure.
- User-facing backup export/import writes `paisatrack_export.ptrack`, a
  passphrase-encrypted archive using Argon2id and AES-GCM. New document flows
  use authenticated chunked records and a final manifest; v1 JSON/AES-GCM
  imports remain supported. Android's Storage Access Framework writes/reads
  only the document the user selects and requires no broad storage permission.
  New archives also contain transaction relationships, counterparty labels,
  category hierarchy, expected-event state, and durable SMS dispositions; all
  remain inside the passphrase-encrypted archive. Older v3 files may omit the
  optional tables and restore safe empty/default state. Restore verification
  uses synthetic archives and local database fixtures only.
- User labels and payment-source nicknames are local metadata. Only masked
  source identifiers are stored; excluding a source or owned transfer from
  analytics does not delete its underlying transaction evidence.
- The Android manifest includes INTERNET permission only for downloading the
  pinned, integrity-checked open-weight models described by ADR 0007/0009. The
  download request carries no user data and inference code paths never open a
  network connection; the permission's scope is documented inline.
- **SMS Admission & Shape-based Triage**: PaisaTrack uses shape-based admission triage rather than a fixed bank allowlist (T-133a). Incoming messages are inspected locally for financial transaction structures (amount, currency, direction, sender) before admission. Non-financial messages (e.g. OTPs, personal chats, marketing) are rejected immediately and never saved.
- **In-App Prominent Disclosure & Consent**: Prominent disclosure precedes the Android runtime SMS permission request, explicitly explaining: (1) what is read (only transactional money texts), (2) that all parsing and storage are 100% on-device with zero cloud uploads, and (3) what happens on decline (manual tracking remains fully available).
- **Capture & Privacy Controls**: Global capture pause and per-sender blacklisting in Settings allow stopping ingestion immediately.

Future statement import must parse locally, avoid retaining the source file,
store only required normalized/source-fingerprint data, and require explicit
user export for any reconciliation report.

## On-device language model

The optional language model is downloaded only after you tap Download
in Settings, stored in app-private storage, and can be deleted there. Inference
is fully offline: prompts and responses never leave the phone. Extraction
prompts may contain the raw SMS text needed to parse a transaction, but that
text is passed only to the on-device model. The model download request contains
no SMS, transaction, account, or other user data.

## Raw SMS Provenance & App Lock (T-147b)

The raw SMS provenance section ("WHERE THIS CAME FROM") in transaction details displays the raw message body (the most sensitive string in the app). It is strictly excluded from home widgets (T-091) and covered by app lock (T-090).

## Proposed assistance metadata (not implemented)

[ADR 0011](decisions/0011-evidence-backed-assistance.md) proposes local field
provenance, confirmed-label learning, review deferrals and minimal evaluation
records. Before implementation, specify retention, encrypted backup/restore,
delete-everything and model/cache invalidation for each added field or table.
Do not extend raw-SMS retention for training or collect financial telemetry.
Receipt/screenshot evidence is future opt-in discovery, not a new permission
or background collection path. See the [plan](plans/smart-transaction-assistance.md).
