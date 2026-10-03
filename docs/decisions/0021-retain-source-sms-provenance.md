# ADR 0021: Retain source SMS provenance

Status: Accepted (owner decision, 2026-10-03; implemented by T-195)

## Context

Every raw SMS used to expire 30 days after receipt
(`AppConstants.rawSmsRetentionDays`, `raw_sms.purge_after`). The nightly purge
first set `transactions.sms_id` to NULL and then deleted the row, so older
transactions lost their "Where this came from" SMS, backups dropped it, and
the source-currency repair could no longer verify them. The owner, who is the
app's only user, said this removal is not wanted.

## Decision

- The SMS behind a transaction (`transactions.sms_id`) or a "Not a
  transaction" disposition (`sms_dispositions.sms_id`) is provenance. It is
  kept for as long as that record exists and is never unlinked by retention.
- Every other raw SMS (unparsed, unreadable, rejected, never linked) is
  removed 7 days after receipt (`AppConstants.rawSmsRetentionDays`), replacing
  the previous 30 days. An unlinked row expires when its `purge_after` has
  passed or it is older than 7 days, which also shortens rows captured under
  the old 30-day rule. The developer flag `raw_sms_retention_days` is retired
  (its stored row is deleted when defaults are seeded) so one constant governs
  capture, purge, backup, and the "Messages we couldn't read" count.
- One shared predicate (`RawSmsRetention` in
  `lib/data/repositories/raw_sms_repository.dart`) defines "linked",
  "expired", and "retained" for the nightly purge, backup export and restore,
  and the unreadable-SMS summary. The purge also clears
  `expected_events.origin_sms_id` values that point at a deleted row, matching
  what restore did before.
- Encrypted backups export linked SMS regardless of `purge_after`, plus
  unexpired unlinked SMS. Restore inserts the archive's raw SMS, restores
  transactions and dispositions, then removes expired unlinked rows in the
  same database transaction. This narrows the ADR 0008 rule "export retains a
  raw SMS row only while `purge_after` is in the future" to unlinked rows.
- Provenance already purged can be re-linked from Settings → "Restore SMS
  sources". It re-reads the inbox through the existing history-import reader
  (no new permission) and links only exact deterministic matches: the
  transaction id is `txn_<provider id>`, the transaction has no source yet, the
  provider id appears once, and every stored evidence span equals the same
  characters of the SMS body. It never creates transactions or changes
  amounts, categories, or other fields; unverifiable rows are skipped and
  counted. Paused capture and paused senders are respected, SMS permission is
  checked first, and repeated taps join the running scan.
- No schema change. Settings "Delete everything" still deletes all raw SMS.

## Backup-size impact (ADR 0008 limits)

Measured on synthetic data with the production chunked exporter: 2,000
template transactions export to 1,936,758 bytes without SMS and 2,615,390
bytes with one 170-character bank SMS each, about 340 bytes per kept SMS
(about 970 bytes per transaction row). The 16 MiB decoded-archive ceiling is
therefore reached at roughly 12,000 SMS-backed transactions instead of
roughly 17,000. The 50,000-row per-table limit is not the binding constraint.
If a real archive approaches the ceiling, raising the ADR 0008 limits needs
its own decision; retention must not be shortened to fit.

## Privacy and consequences

Raw SMS stays on the device inside the encrypted database and inside
passphrase-encrypted backups (ADR 0002, ADR 0008); nothing is uploaded. More
message bodies are kept for longer, which the privacy notes disclose. The
on-device footprint grows by roughly the same 340 bytes per linked SMS.
The app has no per-row hard delete today: "Not a transaction" keeps the row
and its disposition, so its SMS stays. "Delete everything" removes all raw
SMS. If a future hard delete removes a transaction, its SMS becomes unlinked
and expires under the 7-day rule.

Rollback: restore the old purge stage. That loses no data beyond the
previous behaviour.
