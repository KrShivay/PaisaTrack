# ADR 0024: Unify transaction-detail confirmation

Status: Accepted for T-200 implementation

## Context

Transaction details can show two separate confirmation actions. The review
banner calls `confirm`, which only changes transaction status; the lower parse
panel calls `confirmParse`, which only records an eligible parse verdict. The
banner also remains visible for low-trust parses after a status-only change,
so neither the label nor the resulting state makes the user's action clear.

ADR 0005 requires explicit review of parsed amount, direction, and merchant
before an eligible parse verdict is recorded. A category confirmation is not
parse evidence and must not train category prediction. Parse verdicts remain
limited by the existing retained-SMS and field-evidence guard.

## Decision

- Present one `Confirm details` action in one review panel. Show the stored
  amount, debit/credit direction, payee, and category for the user to check.
- In one repository transaction, resolve `needs_review`/`asked` status and
  record a parse verdict only when the existing `_canConfirmParse` guard
  succeeds. Rows outside review status may record only an eligible parse
  verdict; they do not gain status-confirmation behavior.
- Reuse the existing parse-verdict marker, provenance, confidence, and ledger
  refresh rules. The legacy parse-only API keeps its existing deterministic
  ID. The unified action uses a unique per-action ID so a stale undo receipt
  cannot delete a later confirmation that reused the legacy ID. Do not change
  amount, direction, payee, category, source, category feedback, template
  promotion rules, or financial eligibility.
- Exclude deleted, non-transaction, and duplicate rows from the action.
  Analytics and payment-source exclusions do not by themselves make a real
  transaction ineligible.
- Return a receipt describing the prior status and whether this action created
  the parse event. Undo restores the prior status metadata and removes only the
  parse event inserted by this action; it preserves any earlier confirmation.
- Keep a busy guard and visible loading state. A no-op or write failure must
  give clear feedback. A successful action shows a confirmed state and does
  not continue asking the same question.

## Consequences

Status resolution and eligible parse evidence cannot diverge on a partial
write. Legacy `confirmParse` behavior and its tests remain intact. No schema,
parser, inference, category-training, or network behavior changes.

Rollback: restore the prior separate controls and use the existing status-only
`confirm` and parse-only `confirmParse` operations.
