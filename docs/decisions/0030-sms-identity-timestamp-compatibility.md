# ADR 0030 — Sent-time SMS identity with legacy compatibility

Status: Accepted for T-201 capture repair, 2026-10-04.

## Evidence

Permission-free RecoveryQA on the Motorola Edge 50 Pro, Android 16/API 36,
exercised the production receiver with a fixed 3GPP PDU and the production inbox
reader with an injected synthetic cursor. With received DATE 60 seconds after
sent DATE_SENT, both paths accepted the same message but produced different
IDs. Marker: `idsMatch=false`, `dateSentRequested=false`,
`timestampDifferenceMillis=60000`. No owner inbox/provider/app data was accessed.
This proves conversion behavior on the physical runtime, not carrier/provider
delivery. See [ADR 0028](0028-synthetic-sms-identity-qa.md).

## Decision

1. Keep the existing hash algorithm and live timestamp identity. Inbox capture
   projects DATE_SENT and hashes a positive sent timestamp; missing/null/zero
   sent time falls back to DATE without fabricating evidence. Receipt DATE and
   inbox ID remain the keyset pagination cursor. Preserve existing receipt-time
   payload/date fallback behavior rather than moving calendar totals silently.
2. When canonical sent-time and old receipt-time hashes differ, carry the exact
   legacy receipt hash as a bounded alternate identity in the native/Dart
   capture payload. Preserve older payload compatibility. These hashes are
   computed from the exact same sender and full body; never fuzzy-match content,
   amounts, account suffixes or transaction dates.
3. Ingestion, batch/catch-up and provenance restoration recognize canonical and
   legacy identities consistently. Resolve an existing raw/transaction identity
   before inserting. Respect any disposition and existing transaction (including
   deleted/excluded rows). Preserve its primary key, source ID, user edits and
   source facts; do not re-key, merge or rewrite history.
4. Conflicting stored claims or multiple distinct transaction matches abstain
   with a content-free failure. Never choose a winner or insert another counted
   payment. Validate exact retained raw sender/body before using its identity;
   provenance relinking additionally retains all existing evidence-span guards.
5. Added model/payload fields are optional, immutable/bounded and transient.
   No database schema or backup encoding change. Unknown/absent sent time cannot
   guarantee live/inbox equivalence; document that residual provider boundary.
6. Validate incoming page claims before writes. Shared aliases with different
   canonical identities or inconsistent sender/body abstain; identical repeats
   remain idempotent. Across DATE-sorted pages, retain only a bounded last
   receipt-timestamp cohort for the current run. Conflicting later entries fail
   without rewriting an earlier committed row. Capacity exhaustion abstains on
   unresolved cohort entries; changing receipt time evicts the cohort. Alternate
   mappings not retained in stored records cannot be compared across separate
   runs without a future durable identity contract.

## Acceptance and rollback

Require physical fixed-PDU post-fix equality, receipt paging proof, native
tests/compilation, and Dart regressions for live/history order, reference-free
payments, repeated imports, stored legacy IDs/dispositions, ambiguity and
provenance restoration. Existing dates/amounts/categories/feedback remain
unchanged. Full suite, encrypted migration, timezone, analyzer, docs and complete
graph review remain required. Revert the scoped code commit; retain all stored
records and compatibility evidence. No owner SMS permissions or APK publishing.
