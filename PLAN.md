# PaisaTrack — delivery plan

Updated 2026-10-03. This is future direction, not a shipped-feature checklist.
Current behavior: [architecture](docs/architecture.md) and
[product status](docs/product-status.md). Executable queue: [TASKS.md](TASKS.md).

## Product priority

Make captured transactions useful with less manual work: recognise the payee,
reuse what the user already confirmed, fill supported details, and ask only
about uncertainty. Then explain and forecast recorded spending with evidence.

## Delivery order

1. Finish T-176 physical-device acceptance (T-179a passed its isolated
   physical recovery run on 2026-10-01); retain capture,
   visibility and recovery release blockers on the board. T-157b and PV-02
   passed independent review and are complete.
2. T-177a: baseline and production-wiring audit. Resolve contradictory legacy
   completion claims before adding duplicate implementations.
3. T-177b–f: safe recognition/memory, scoped correction/undo, grouped review,
   category reuse and a measured staged rollout. [Full feature plan](docs/plans/smart-transaction-assistance.md).
4. T-178a is complete. T-178b–d cover validated forecast ranges, grounded
   English/Hinglish questions and evaluation.
   [AI report](docs/reports/grounded-ai-opportunities.md).
5. T-102: local statement reconciliation; T-177g: optional receipt evidence
   feasibility. Neither is required for the initial learn-once flow.
6. Finish remaining refund/expected-event product gaps (T-100/T-101), then
   category budgets (T-098). Existing link/event code must be reused and audited,
   not rebuilt from old design briefs.

This order does not waive release blockers or claim dependencies have passed.
New work stays Backlog until its child brief is groomed; one implementation task
at a time. Briefs: [T-177](docs/tasks/T-177.md), [T-178](docs/tasks/T-178.md).

## Remaining product contracts

| Outcome | Required behavior |
|---|---|
| T-102 statements | Local CSV preview/account mapping; reference-first guarded matching; idempotency; ambiguity review; rollback; never overwrite user corrections |
| T-100 refunds/reimbursements | Full/partial/many links; preserve source rows; explain net totals; verify existing link implementation before planning gaps |
| T-101 expected payments | Expected events separate from settled payments; date/amount ranges; guarded settlement match; snooze/cancel/missed/price-change states |
| T-098 category budgets | Dedicated category/month model; net-spending consistency; explained exclusions; no automatic rollover; current global prototype is not completion |
| T-090/T-091/T-094 release | App lock before privacy-safe widget; recovery, performance, accessibility and distribution evidence |

## Non-negotiable boundaries

- Financial data and inference stay on-device; no new cloud service or paid
  runtime dependency. Model availability never blocks capture.
- Source amount/date/reference/identity evidence stays separate from edits and
  derived labels. No invented payments, items, purpose, balances or locations.
- Confirmed rules outrank suggestions. Uncertainty can remain unresolved.
- Historical changes, identity merges and reconciliation have previews and undo
  where practical; bulk assistance requires full correction/rule/feedback undo.
- One calendar and financial-eligibility contract across queries, forecasts,
  insights and budgets. Pending events are not settled spending; transfers and
  linked refunds follow the verified accounting contract, not merchant-name guesses.
- Schema changes require an ADR, additive migration, backup/delete coverage and
  migration tests. [ADR 0011](docs/decisions/0011-evidence-backed-assistance.md)
  is accepted in part; this plan does not approve any additional schema, model,
  or runtime change.

## Defaults to preserve or validate

- Keep the current model/runtime selection in ADR 0009; benchmark before change.
- Raw-SMS retention follows the existing privacy policy; new inference is not a
  reason to retain messages longer.
- Non-INR amounts retain currency; no invented exchange rates.
- Profile name remains optional. Category creation and descriptions are optional.
- Daily Sort skip and persistent “don't remember” are distinct states; T-177d
  must specify migration without treating either as confirmation.
- Automated refund thresholds and category confidence require measured precision;
  an old numeric default is not evidence of safe automation.

## Verification and history

Implementation follows [COLLABORATION.md](COLLABORATION.md). Documentation-only
work checks links, board invariants, internal consistency and whitespace; it
must not report application tests as run unless actually executed.

Older execution orders, completed-ticket details and model-specific umbrella
queues are superseded. Use the [short archive reference](docs/archive/planning-cleanup-2026-09.md)
and Git history; retain unfinished child tasks until verified closed.
Legacy PLAN section references resolve to current architecture, schema, privacy
and ADR documents; do not recreate a duplicate historical plan.
