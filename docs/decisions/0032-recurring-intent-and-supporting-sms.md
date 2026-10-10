# ADR 0032 — Per-transaction recurring intent and supporting SMS links

Status: Accepted (owner request, 2026-10-10)

## Context

The owner asked that (a) any transaction can be marked recurring or
non-recurring, and (b) related messages — dividend advices, RD instalment
notices, pre-debit loan EMI notices and UPI collect/payment requests — are
captured and shown together on the transaction they describe. Today a
transaction has exactly one source SMS (`transactions.sms_id`); other messages
about the same money movement expire after 7 days as unlinked raw SMS.

## Decision

Schema v20, additive only:

- `transactions.recurring_override` (nullable text): `recurring`,
  `not_recurring`, or NULL for automatic detection. User intent wins over the
  detector: `not_recurring` rows are excluded from recurring detection input;
  `recurring` rows are surfaced as user-marked recurring even when the
  detector has no series. Amounts, categories and totals are unchanged.
- `sms_transaction_links (sms_id, transaction_id, kind, basis, confidence,
  created_at)`, primary key `(sms_id, transaction_id)`, index on
  `transaction_id`. Kinds: `dividend`, `rd_instalment`, `emi_notice`,
  `collect_request`, `related`. Like `sms_dispositions` it stores no content
  and has no foreign keys.
- A raw SMS referenced by `sms_transaction_links` is linked provenance under
  ADR 0021 and is retained with its transaction. Encrypted backups export and
  restore the table; restoring an older archive leaves it empty and
  `recurring_override` NULL.
- Linking is deterministic and conservative: exact amount (paise) and source
  currency bucket, a bounded time window, and a corroborating account suffix,
  reference, or counterparty. Ambiguous candidates abstain. Supporting
  messages never create, change or delete transactions or amounts.

## Consequences

The detail screen lists the primary SMS, echo duplicates' SMS and supporting
SMS together. Retained message bodies grow modestly (about 340 bytes each,
ADR 0021 measurement). Rollback: the previous release ignores the column and
table; no data is rewritten.
