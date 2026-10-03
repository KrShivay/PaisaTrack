# ADR 0025: Confirmed-history category suggestions

Status: implemented and independently reviewed for gated T-177b-S1; production
rollout is not approved by this ADR.

## Context

The categorizer has an optional merchant-memory hook, but production does not
wire it. Its result uses the normal categorization type and can be assigned by
the auto-capable capture ladder. Wiring it directly would let memory silently
change captured rows before the holdout and staged-release gates pass.

The app already stores category prediction provenance in `confidence_json`,
explicit category corrections in `feedback`, exact name/VPA evidence in
`payee_evidence`, and reversible user corrections. Status confirmation alone
does not establish that the category is correct. T-200's detail confirmation
also records parse/status evidence only; it is not category training evidence.

## Decision

- Build a read-only suggestion lookup for transaction detail, outside the
  capture `Categorizer` ladder. The separate explicit acceptance path changes
  only category and records a guarded Undo receipt. The default production gate
  is false and is only overridden by synthetic tests in T-177b-S1.
- Suggest only when at least two distinct eligible source transactions for the
  exact current raw VPA (the normalized evidence key is only an indexed
  candidate lookup), or exact normalized name key when no VPA is present, have
  explicit category outcomes and every current outcome names the same existing
  category. Corroborate names against current transaction rows so a stale
  evidence index cannot teach an old identity. Exclude the current transaction,
  manual entries, deleted, nontransaction, duplicate, unsettled, and
  analytics-excluded rows. A name-only lookup abstains when its matching
  history contains multiple VPAs.
- An explicit category correction contributes its current category only when
  the latest category feedback still agrees with the transaction and its
  context is an explicit user category action. Otherwise an outcome requires a
  current `confirmed` status backed by the existing `activity_confirm` or
  `sort_confirm` feedback context and valid category prediction provenance.
  Status-only T-200 confirmation, parse-confirm feedback, skips, automatic
  labels, and undo records do not become category outcomes.
- Existing category edits and matching explicit rules take precedence. Mixed
  outcomes, deleted categories, missing provenance, or ambiguous identity
  produce no suggestion. Currency and financial eligibility remain separate;
  a VPA/person label does not change spending inclusion.
- Acceptance rechecks the current suggestion and applies only category plus one
  explicit feedback row in a transaction. Undo requires an exact before/after
  transaction snapshot and feedback receipt, so it cannot overwrite later
  edits. It does not change status, amount, direction, parse verdict, source
  evidence, payee identity, financial eligibility, or future rows. It does not
  call `correctCategory`, which confirms status and can create a rule.
- Suggestions remain unavailable in production until the T-177a evidence and
  device exit criteria are complete and T-177f authorizes the suggestion-only
  stage. No automatic-assignment threshold or rollout is authorized here.

## Consequences

No new schema or retained data is needed. Existing exact payee evidence and
explicit feedback are queried on-device. The suggestion provider is a separate
read path, and its default-off gate is covered by tests. Tests must show
provider abstention and detail UI absence by default, then exercise the
suggestion and explicit category-only Undo with an injected enabled gate.

This decision does not complete T-177a or approve any production prompt,
automatic assignment, merchant merge, or cross-capture provider wiring.
