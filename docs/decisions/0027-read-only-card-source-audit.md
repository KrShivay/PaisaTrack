# ADR 0027: Isolated read-only card source audit route

Status: Accepted for T-190a1 host source-audit implementation only.
No card accounting, ownership/instrument mutation or schema is approved.

## Context

Source rows infer identity from account hint and channel. Neither card channel
nor the current owned flag proves a credit-card product or explicit ownership.
The existing paymentSourcesProvider calls reconcileOwnedTransfers before
watching sources, so a report entered through that page would mutate the ledger.
The [source audit](../reports/T-190a1-card-source-audit.md) records the original
preparation. The bounded repository and separate route now implement this
engineering contract; [T-190a1](../tasks/T-190a1.md) records host verification.

## Decision

Add a sibling Settings route backed by a separate read-only repository/provider.
Read stored source metadata and SQL aggregates, and page candidate rows with
deterministic cursors. Do not call paymentSourcesProvider, updateSource or
reconcileOwnedTransfers. No source/SMS/relationship writes or accounting totals
belong to the audit. Show inferred/product/ownership uncertainty explicitly,
masked identifiers and absent institution/nickname labels without guessing.

Evidence-supported stored identity conflicts may be reported. Already-collapsed
historical collisions are unobservable; no issuer is inferred from sender text
or a masked suffix. Keep currency evidence separate and report incomplete
coverage when a bounded read has more pages. Preserve both source rows and
existing flags/links exactly.

## Consequences

The owner can inspect uncertainty without changing transfer inclusion. Tests
must prove real route access does not invoke the existing mutating provider,
and seeded source/transaction/link/feedback/aggregate values remain identical.
No additional persisted data, migration or backup encoding is needed.
[T-190a1](../tasks/T-190a1.md) owns this bounded implementation; later ownership,
payment allocation, shared refund semantics and statement work retain the
proposed [ADR 0020](0020-credit-card-accounting.md) gates.
