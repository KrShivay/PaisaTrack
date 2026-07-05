# Privacy

PaisaTrack is local-first:

- Raw SMS and transactions never leave the device by default.
- Historical inbox backfill (T-023) reads `Telephony.Sms.Inbox` on-device only; the
  filtered messages flow straight into the encrypted local store and message bodies
  are never logged, even on error paths.
- Raw SMS retention is capped by the purge policy in PLAN.md.
- Optional cloud features must be feature-flagged and receive only anonymized data.
- Release builds must not log raw SMS bodies.
