# ADR 0020: Credit-card purchases, payments and liability accounting

Status: Proposed. Owner accepted the recommended product defaults on
2026-10-10 (decisions 1–6 and 8 in the
[plan](../plans/credit-card-accounting.md#owner-decisions)); formal acceptance of
this ADR's accounting boundaries remains T-190s1.

## Context

Card SMS parsing and generic payment-source rows exist, and the ledger already
has lifecycle state, duplicate references, owned-transfer IDs, transaction
links and a shared settled-spend predicate. Those pieces do not currently form
a card-liability accounting flow: source identity is inferred from account hint
and channel, while statement notices are nontransactional and payment
allocations/outstanding are not maintained. See the [grounded card plan](../plans/credit-card-accounting.md)
for current-state citations, scenario coverage, test fixtures and open product
choices.

## Proposed decision

- A confirmed, settled card purchase is spending once at transaction date.
  Authorization holds, declines, reminders and duplicate echoes are not
  settled spend.
- Assign exactly one canonical liability delta to each accepted source event:
  purchase charge, fee/interest charge, payment receipt, payment return,
  purchase reversal, refund credit, cashback credit, EMI conversion credit, or
  cash advance. A linked/allocation-classified credit is excluded from generic
  posted-credit application. A bank debit and card confirmation can represent
  only one payment event. EMI conversion credit has zero total-liability delta.
- A linked `reverses` credit nets the original purchase in its purchase period.
  A linked `refunds` credit is distinct and follows the owner-approved refund
  period rule. Preserve posting-period evidence and captured source amounts.
- A bill payment from an owned bank source to the user's own card is an owned
  transfer that repays card liability. It never adds spending. Reuse
  `transfer_leg` and existing owned-transfer handling when both payment legs
  are actual transaction rows; represent card-level or split allocations with
  an explicitly typed additive relation if the existing transaction-to-
  transaction link cannot express the endpoint safely.
- Preserve each captured source row. Model settlement, duplicate, reversal,
  refund, repayment and statement relationships as links or separate typed
  evidence/decision rows. Reuse current link kinds where their endpoint and
  accounting semantics match; do not mutate source amounts to net totals.
- Derive outstanding and available credit from canonical event deltas and
  dated issuer snapshots. Do not separately subtract allocated payments,
  linked reversals/refunds or classified credits as generic posted credits.
  Do not store a cached outstanding amount as truth. Available credit remains
  unknown if the limit is unknown. Statement snapshots are immutable evidence
  and never overwrite transaction history.
- Preserve source currency exactly. Do not invent an FX rate or combine
  currencies; follow [ADR 0017](0017-source-currency-fidelity.md).
- Any schema change must be additive and include migration, backup/restore,
  reset/delete, undo, and migration-test coverage. Candidate additions are a
  nullable payment-source instrument type, immutable statement snapshots, and
  a typed card allocation table only if tests prove existing links insufficient.
  These are candidates, not approved schema.

**No schema is approved yet.** ADR acceptance, schema design and each
implementation phase require separate grooming and review. T-190 is a planning
deliverable, not authorization to change the schema or implementation.

## Alternatives considered

1. **Count bill-payment debits as ordinary spending.** Rejected because it
   counts the purchase and repayment twice.
2. **Use only a mutable card balance column.** Rejected because it loses source
   evidence, cannot explain conflicting statements, and is difficult to undo or
   restore faithfully.
3. **Rewrite purchases with refund/payment net amounts.** Rejected because it
   destroys original amounts and obscures refund timing and statement history.
4. **Treat every card-channel source as an owned credit card.** Rejected because
   current channel/account inference does not prove product type or ownership.
5. **Add a wholly separate card ledger immediately.** Deferred; first test
   whether existing transactions, links, event tables and typed additive
   allocation/snapshot rows can satisfy the contract without parallel facts.

## Consequences

- The shared financial-eligibility contract will need link-aware net-spend
  semantics while keeping pending, failed, repayment and duplicate rows out.
- Refund period, cashback/rewards, card-charge category and period, cash advance,
  EMI, overpayment and statement-period presentation need owner decisions or
  must remain explicitly unresolved. Proposed cash-advance default is a
  liability increase without categorized spend; posted fees/interest remain
  card charges.
- Source audit and ownership mutation are separate slices. Any ownership or
  instrument change that invokes transfer reconciliation needs a preview of
  affected rows/totals and durable undo. Reconciliation must remove stale
  generated `transfer_leg` edges before card-payment reuse.
- New linked domain state must follow [ADR 0016](0016-backup-domain-state-and-restore-order.md)
  restore ordering and older-archive compatibility, and must respect raw-SMS
  retention in [ADR 0008](0008-bounded-encrypted-backups.md).
- Review explanations and correction/undo should reuse the evidence-backed
  contract in [ADR 0011](0011-evidence-backed-assistance.md) and the open
  [PV-04 contract](../tasks/T-172.md).
- Synthetic fixtures can verify parser/accounting behavior; they do not satisfy
  physical-device acceptance or claim real issuer coverage.
