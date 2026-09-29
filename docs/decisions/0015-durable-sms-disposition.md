# ADR 0015: Durable “Not a transaction” disposition

**Status:** Accepted for T-185

## Context

A user may correct a false-positive SMS import. Hiding the transaction only in
the current list or an in-memory Undo action is insufficient: the same stable
SMS identity can be encountered again during history/catch-up, and raw SMS
content is intentionally purged on schedule. Reusing `is_deleted` would also
conflate two different user decisions.

## Decision

Persist a content-free disposition keyed by provider SMS ID and linked by
transaction ID, plus a dedicated `transactions.is_not_transaction` projection
for ledger and intelligence queries. The disposition table has no foreign key
to `raw_sms`, so retention does not erase the decision. Marking atomically sets
the transaction flag, records the disposition, unlinks/reopens fulfilled
expected events, and removes derived payee evidence. Restoring atomically clears
the flag and disposition, rebuilds payee evidence, and reconciles expected
events. The detail action offers immediate Undo; Settings keeps a durable list
that can reverse the decision after restart or raw-SMS expiry.

Both encrypted archive encodings export and restore dispositions. Older v3
archives may omit this optional table; missing disposition rows restore as an
empty set and older transaction rows default `is_not_transaction` to false.

## Privacy and consequences

The durable row stores only SMS ID, transaction ID, disposition, and correction
timestamp. It never stores message content, sender, receipt time, or an extension
to raw-SMS retention. The flag excludes the row from Activity/review, financial
aggregates, assistant queries, recurrence/insight inputs, expected-event
reconciliation, and payee learning. Deterministic derived reads are refreshed
after each correction while preserving user-paused recurring series state.

## Rollback

Rolling back the UI must not erase disposition rows. A later build can migrate
the additive flag/table forward and keep suppression decisions; database reset
continues to erase the full local store through the existing generation reset.
