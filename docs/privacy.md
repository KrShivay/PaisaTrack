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
- Developer tooling: the dev screen's transactions-JSON export is compiled out
  of release builds (`kDebugMode`), writes only to the app-private documents
  directory (never external storage), and is retrievable only via `adb run-as`
  on debuggable builds. Bank statements and reconciliation reports used for
  Phase 1 verification live in the gitignored `BankStatement/` folder and are
  never committed; the same applies to on-device transaction exports
  (`export.json`, gitignored).
