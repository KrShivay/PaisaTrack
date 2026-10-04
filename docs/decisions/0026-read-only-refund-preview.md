# ADR 0026: Read-only refund preview boundary

Status: Accepted for bounded T-100a-S1 engineering preparation only.
No persisted relationship, accounting-period policy or schema is approved.

## Context

The existing refund correlator has no production caller and does not enforce
unique candidates or cumulative refunds. Existing link storage does not define
accounting. The owner refund-period decision is still open; adding a write path
would prematurely choose behavior. Card and non-card flows need one review
contract grounded in persisted evidence.

## Decision

Provide a read-only repository preview in a consistent database snapshot.
Use exact stored reference evidence, same SourceCurrency bucket, and existing
eligible spending-debit rules. Abstain on ambiguity. Preserve both source rows
and dates, and report existing adjustment and remaining refundable amount
without applying it to any calendar total. Reject over-cap and malformed or
conflicting links instead of truncating or guessing. Card channel and inferred
ownership never establish a credit-card product or confirmed ownership.

No writes, new tables, backup payload, capture/provider integration, automatic
linking or user-facing enablement belong to this slice. No merchant-prefix
fallback is authorized. The preview cannot authorize confirmation; a later
write operation must recheck the same guards atomically and support durable
Undo under an accepted persistence contract.

Use exact complete raw-reference equality against the existing reference
index. This conservative lookup may abstain on differently formatted references;
it must not extract a shared digit run or silently infer equivalence. Preserve
arbitrarily late posting dates rather than inheriting the correlator's unapproved
30-day heuristic. The original purchase must precede or coincide with its credit.

Pair arithmetic uses checked decimal units internally, supporting at most six
fractional source decimal places without assuming an ISO currency's minor-unit
denomination. Source doubles are never rewritten. Unsupported precision or a
display value that cannot round-trip exactly abstains explicitly. Bound lookup
size and return a limit outcome rather than selecting from incomplete results.

## Consequences

Tests can verify review arithmetic and abstention with synthetic persisted
rows while the owner accounting choice remains pending. The API is a verified
foundation, not shipped refund tracking or real-data accuracy evidence.
[T-100a-S1](../tasks/T-100a-S1.md) records acceptance and delivery boundaries;
[T-100](../tasks/T-100.md) retains the remaining accounting, persistence,
review/Undo and aggregate gates. ADR 0020 remains proposed.
