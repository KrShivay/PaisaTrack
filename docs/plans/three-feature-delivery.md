# Three-feature delivery plan

Status: proposed; planning only. No task is promoted to Ready, no owner gate is
cleared, and no schema or product behavior is approved by this plan. Deliver
one implementation child at a time. Current behavior remains defined by
[`docs/architecture.md`](../architecture.md), [`docs/schema.md`](../schema.md),
and accepted ADRs. This sequence refines the existing [T-177 assistance
plan](smart-transaction-assistance.md), [T-100 refund brief](../tasks/T-100.md),
and [T-190 card plan](credit-card-accounting.md) without replacing their
acceptance gates.

## Delivery order

1. **Repeat-payee category suggestions** — first feature, through a bounded,
   suggestion-only T-177b slice. T-177a's owner-selected chronological holdout,
   approved/revised thresholds, and device capture acceptance remain open.
   Until that gate passes, build and verify only deterministic suggestion logic
   and its opt-in-disabled integration contract; do not enable production
   prompts or automatic labels. This preserves useful progress without treating
   synthetic replay as accuracy evidence.
2. **Refund-to-original-payment links** — T-100a accounting contract, then
   guarded relationship persistence, user preview/review/Undo, and finally the
   shared net-spending contract. T-100a owner accounting decisions and PV-04
   explanation/eligibility work remain prerequisites where their contracts
   apply.
3. **Credit-card bill and repayment tracking** — start with T-190a1's read-only
   source audit, then confirmed ownership review, payment allocation, lifecycle
   and refund handling, derived liability, and statement review. This remains
   last because it depends on T-100 refund semantics, PV-04, and eventually
   T-102 statement reconciliation. ADR 0020 is proposed; no schema is approved.

This order does not close T-176, T-177a, PV-04, T-100, T-102, accessibility,
backup, or physical-device gates. Keep their current board status until each
acceptance contract is met.

## Current continuation boundary (2026-10-04)

- T-177b-S1 is host-complete on main at `d573881`; do not recreate its
  suggestion lookup or capture replay. Suggestions remain default-off.
- The merchant gate audit confirms that the consented chronological period,
  cohort/threshold decision, independent labels and physical live/resume
  evidence remain unavailable. Production shadow scheduling additionally
  depends on T-177d/e, isolation review and T-115 profiling. A future
  threshold-agnostic cohort/Wilson extension to the existing replay report can
  verify synthetic metric arithmetic; it cannot clear any rollout gate.
- [T-100a-S1](../tasks/T-100a-S1.md) is bounded read-only refund preview
  preparation under [ADR 0026](../decisions/0026-read-only-refund-preview.md).
  It exposes no write or calendar aggregate path. The owner refund-period
  question remains unanswered; T-100a/b/c are still open.
- [T-190a1](../tasks/T-190a1.md) adds the isolated read-only Settings source
  report under [ADR 0027](../decisions/0027-read-only-card-source-audit.md).
  Ownership confirmation, liability, bill repayment and refund accounting
  wait for their contracts; this audit does not approve ADR 0020.

## 1. Repeat-payee category suggestions

### Shipped foundation and gap

`Categorizer` supports an optional merchant-memory resolver and
`computeMerchantMemoryHit`, but `categorizerProvider` supplies neither the
memory nor LLM callback. Explicit rules, seed mapping, local classifier, and
fallback are active. Payee identity is resolved across live, imported, and
catch-up capture; similarity alone remains a review suggestion. Existing user
correction feedback and receipt-guarded Undo contracts should be reused.
`correctCategory` cannot be reused directly because it confirms status and may
create a future rule; suggestion acceptance is category-only.

### First slice: T-177b-S1, exact-identity suggestion only

For a new transaction with an exact, unambiguous, already-resolved merchant or
payee key, show one existing category as a suggestion when at least two
eligible, explicitly confirmed outcomes agree on it. A user can accept or
choose another category. Do not silently assign it, create categories, treat
automatic labels/skips as confirmation, infer a payee merge, or exclude a
personal-VPA payment from spending. Rules remain higher priority, existing
edits win, and mixed-use or conflicting histories abstain. Keep the feature
disabled in production until T-177a's owner holdout and device gates are
accepted; no automatic-label threshold is changed in this slice.

Acceptance changes only the category and records its explicit provenance. It
does not confirm status, create a future rule, or alter parse/source evidence.
Undo uses an exact before/after receipt and refuses to overwrite a newer edit.
The detail entry point is the first implementation slice; live, history, and
resume coverage remain later rollout parity work.

The gate is specifically T-177a's missing consented chronological holdout,
owner-approved/revised cohort and metric thresholds, and device coverage for
the staged production rollout. These gates apply before production suggestions
are enabled; the completed synthetic replay and threshold safeguard do not
clear them. T-177a's 98% audited precision and 95% interval lower-bound target
is evidence for broad automation, not a basis to enable this disabled slice.

### Acceptance evidence

- Unit tests for two or more explicit confirmed same-category outcomes, mixed
  categories, one outcome, deleted category, rule priority, missing model, and
  exact name/VPA identity separation.
- Repository tests prove only explicit category confirmation/correction is
  evidence; auto labels, status-only confirmation, silence, deferral, and manual
  transactions do not train memory. Currency and financial eligibility stay
  separate from category evidence.
- Repository tests prove suggestion acceptance changes only category, records
  one explicit outcome, and uses an exact receipt that refuses stale Undo. The
  detail panel test proves the provenance explanation and explicit accept
  action; the production gate defaults disabled. Live/history/resume parity is
  a later staged-rollout requirement.
- Holdout/device evidence is a later release exit, not simulated by fixture
  arithmetic. Report repeated/new/mixed payee precision, coverage, incorrect
  accounting exclusions, and decisions per 100 eligible transactions.

**Dependencies and decisions:** [T-177a/b](../tasks/T-177.md) evidence/owner gate; T-177b exact identity
and confirmed-history contract; T-157b shared correction/Undo; ADR 0011 evidence
boundaries; current categories only. No new schema unless T-177a's map proves
existing feedback/provenance storage insufficient. No additional owner decision
is required to implement disabled suggestion-only logic; release thresholds
remain an explicit T-177a owner decision.

**Implementation impact note:** the earlier T-177 planning snapshot marked
`Categorizer.categorize` CRITICAL (11 impacted symbols, 3 direct references,
5 execution groups). The planning-time GitNexus snapshot was PaisaTrack at
`6e2d08784e906bbd8a1ef9e4118a22e351f4741a`, indexed 2026-10-03, and reported
`TransactionLinks` as CRITICAL and `PaymentSourceRepository` as MEDIUM. Re-run
impact against the exact production symbol before any code edit; these reports
are planning context, not edit authorization. The `categorizerProvider` name
itself had UNKNOWN/zero resolved callers, so verify its usages by text search
when implementation begins.

## 2. Refund-to-original-payment links

### Shipped foundation and gap

The ledger already stores `echo`, `settles`, `reverses`, `refunds`,
`repays`, and `transfer_leg` relationships. `EventCorrelator.correlateRefund`
can match by reference or a unique counterparty/amount candidate, but current
source audit found no production caller; ingestion's current relationship write
is an `echo`. `FinancialEligibility` currently excludes invalid, non-settled,
duplicate, analytics-excluded, and owned-transfer rows, but does not net refund
edges. `FinancialEvents.netAmountPaise` has no current repository consumer.

The [source audit](../reports/T-100a-refund-source-audit.md) inventories current
callers, storage/backup gaps, synthetic cases, and unresolved owner decisions.
It records no executed tests and does not approve the proposed contract.

### Slices and visible behavior

1. **T-100a — audit and accounting contract.** Verify every aggregate caller,
   source direction/currency rules, full and partial refunds, reversals,
   multiple refunds, over-refund, ambiguous candidates, and period treatment.
   Agree what users see before enabling persisted links.
2. **T-100b1 — guarded relationship persistence.** When exact reference evidence
   yields one compatible original payment, persist a `refunds` link while
   retaining both source rows and amounts. Ambiguity remains unlinked; no
   merchant-name-only or cross-currency match. Repeated ingestion is idempotent.
3. **T-100b2 — preview, review, and durable Undo.** Transaction detail explains
   “Refund of [original]” with both amounts and dates. User review shows the
   proposed original and accounting effect; stale previews refresh. Undo removes
   only the relationship and restores prior projection, preserving source rows
   and newer independent edits.
4. **T-100c — canonical net totals.** Dashboard, trends, Ask, and future budgets
   use one link-aware calculation. A reversal nets the original in its period;
   a refund follows the owner-approved refund-period rule. Preserve gross source
   history and separately explain posting-period evidence.

### Acceptance evidence

- T-100a synthetic scenarios: one full refund, two partial refunds, attempted
  over-refund, ambiguous same-amount candidates, reversal, repeat import,
  different currencies, and out-of-window reference.
- T-100b1 repository tests: exact reference link, review-only unique eligible
  fallback candidate, ambiguity abstention, same-currency guard, no source-row
  mutation, duplicate import idempotency, and link uniqueness. Persisting a
  fallback link requires an owner-approved evidence contract; merchant-name
  or amount-only similarity never persists a link automatically.
- T-100b2 tests: complete before/after preview, stale-preview refresh, confirm,
  restart, Undo, and refusal to overwrite a newer edit; UI shows original and
  refund amounts/dates and remains accessible.
- T-100c parity tests assert the same full/partial/reversed results in
  dashboard, assistant, trends, and budget-facing query paths; transfer,
  pending, duplicate, excluded, and non-spending-category controls stay out.

**Dependencies and decisions:** [T-100](../tasks/T-100.md) owner accepts accounting semantics;
T-157b shared correction/Undo; PV-04 lifecycle and exclusion explanations;
T-165c only if amount representation changes. ADR 0017 requires source currency
identity and forbids FX guesses. T-100 is proposed work; existing helper/link
storage does not mean refund tracking is shipped.

## 3. Credit-card bills and repayments

### Shipped foundation and gap

Card-related SMS parsing and generic payment-source rows exist. Payment-source
ownership can be inferred from account hint and channel, and settings support
source ownership/analytics flags; neither inference nor a `card`-looking channel
proves card product type or user ownership. Existing owned-transfer
reconciliation handles owned bank transfers. There is no current card payment
allocation, statement snapshot, card liability projection, or card bill review
flow. Generic transaction links alone do not define net totals.

### Slices and visible behavior

1. **T-190a1 — read-only source audit.** Report source kind, masked identifier,
   institution, inference basis, and rows needing ownership review. No writes or
   reconciliation.
2. **T-190a2 — ownership/instrument decision.** User sees affected rows and
   before/after totals, confirms one source decision, and can Undo durably. Do
   not infer ownership or run reconciliation before confirmation.
3. **T-190b2 — payment allocation.** Link an accepted owned-bank debit to a
   confirmed card liability only after review. The purchase remains spending
   once; repayment never adds spending. If a card-side confirmation echoes the
   same bill payment, apply one liability event total.
4. **T-190c/d — lifecycle and refunds.** Holds and declines add no settled
   spend; settlement is one event; returns/reversals and full/partial refunds
   retain source rows and reuse T-100. A failed or reversed bill payment restores
   liability once without adding spend.
5. **T-190f1/f2 and g1 — statements and explanation.** Keep dated issuer due,
   limit, and available-limit snapshots as immutable evidence; derive
   per-currency liability from accepted events. Explain statement variance,
   unknown limit, allocation, and Undo. An available-credit value stays unknown
   without explicit matching-currency limit evidence.
6. **T-190h1/h2 — statement reconciliation.** Reuse the T-102 local CSV preview,
   idempotency, ambiguity, and rollback contract; map a confirmed card source
   only after shared importer acceptance. Unmatched lines remain unresolved and
   never create confirmed spend automatically.

The [card source audit](../reports/T-190a1-card-source-audit.md) records current
inferred identities, ownership writes, transfer behavior, and missing ledger
contracts. Its original source-only preparation is separate from the bounded
[T-190a1 host implementation](../tasks/T-190a1.md); neither approves ownership,
schema, or accounting changes.

### Acceptance evidence

- Read-only audit proves no owner, instrument, analytics, relationship, or
  aggregate write. Ownership preview/confirm/Undo proves exact affected rows,
  totals, restart behavior, and restore behavior.
- Synthetic sequence: purchase ₹1,200 + bill payment ₹1,200 returns liability
  to zero while spend remains ₹1,200; duplicate bank/card payment evidence does
  not apply twice. Partial payment ₹300 + refund ₹200 yields ₹700 liability and
  ₹1,000 net spend; the prior ₹1,200 statement snapshot stays unchanged.
- Failure sequence: payment plus equal return yields no lasting liability
  reduction and no spend; authorization hold/decline add zero settled spend;
  duplicate echo contributes once. Repeat reconciliation and Undo are stable.
- Currency sequence: USD purchase and INR markup stay in their currency buckets;
  no FX conversion or cross-currency link is inferred. Statement import tests
  prove idempotency, same-amount ambiguity, corrected-source protection, and
  rollback without a second purchase.
- Schema slices, only after ADR acceptance, include additive migration,
  generated schema, foreign-key failure, older-archive restore, backup/reset/
  delete coverage, and undo. Fixtures use synthetic issuers, masked IDs, and
  fabricated references only.

**Dependencies and decisions:** [T-100](../tasks/T-100.md) relationship review and net
contract; T-190a1/a2 ownership; T-190b1 stale generated `transfer_leg` cleanup
(closed by T-165b); PV-04 explanations and T-164c/d visibility; ADR 0016 backup
order; ADR 0017 source currency; [ADR 0020](../decisions/0020-credit-card-accounting.md)
remains proposed; [T-102](../tasks/T-102.md) precedes T-190h. The detailed
phases and synthetic scenario map are in [T-190](../tasks/T-190.md) and the
[card plan](credit-card-accounting.md).
The card plan leaves refund-period default, `Card charges` category and period,
cash-advance spend, rewards/cashback, overpayment, statement-cycle view,
add-on-card grouping, and incomplete EMI presentation as genuine owner
decisions. Keep unresolved behavior explicitly reviewable until decided.

## Verification for each documentation or implementation child

For this plan, validate Markdown links, proposed-versus-shipped wording, and
`git diff --check`; application tests are not appropriate for prose. Each later
implementation child follows its task's named focused and full checks, analyzer,
migration/backup checks when schema changes, and GitNexus impact/change review.
Do not report this plan as evidence that any implementation or release gate
passed.
