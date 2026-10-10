# PaisaTrack — delivery plan

Updated 2026-10-10. This is future direction, not a shipped-feature checklist.
Current behavior: [architecture](docs/architecture.md) and
[product status](docs/product-status.md). Executable queue: [TASKS.md](TASKS.md).

## Product priority

Owner direction (2026-10-10): the app must be smooth (no flicker), fast and
intelligent, and ship faster; full UI/UX rewrites are allowed. Make captured
transactions useful with less manual work: recognise the payee, reuse what the
user confirmed, separate spending from transfers and income honestly, and ask
only about real uncertainty. Then turn every SMS field into source-faithful
facts and explain them with evidence.

## Delivery order

Waves, parallel groups, hot-file locks and the dependency ledger live in the
[roadmap](docs/plans/roadmap.md); this list is the priority summary.

1. **Smooth and honest (P0):** T-203 import flicker/speed; T-205 categorisation
   and income gap ([plan](docs/plans/categorisation-v2.md)); T-210 test speed
   so implementation can iterate.
2. **Foundations (P1):** T-204 icon system and UX v2 ([plan](docs/plans/ux-v2.md));
   T-208 performance budgets ([plan](docs/plans/performance.md)); T-211
   taxonomy; T-207 extraction audit and fact model
   ([plan](docs/plans/intelligence-v2.md)).
3. **Owner-approved schema:** T-207 facts store and timelines (ADR 0034),
   integer minor-unit money T-165c (ADR 0033), customisable dashboard
   (ADR 0035), payee review memory (ADR 0036).
4. **Money semantics:** T-100 refunds (window decided; attribution T-209),
   T-190 card accounting, T-098 budgets, T-102 statements.
5. **Grounded AI and release:** T-178b–d, T-177b–g, T-171b budgets,
   T-090/091/094. Device gates in `In Review` run in batched owner sessions.

## Remaining product contracts

| Outcome | Required behavior |
|---|---|
| T-205 categories | Direction-aware deterministic cue rules; explicit per-payee "spending or transfer?" decisions with preview/Undo; no amount changes |
| T-207 facts | Span-verified facts linked to raw SMS; never transactions; model may only locate spans |
| T-102 statements | Local CSV preview/account mapping; reference-first guarded matching; idempotency; ambiguity review; rollback; never overwrite user corrections |
| T-100 refunds | Full/partial/many links; 31-day lookback; one attribution switch; preserve source rows; explain net totals |
| T-101 expected payments | Expected events separate from settled payments; guarded settlement match; snooze/cancel/missed/price-change states |
| T-098 category budgets | Dedicated category/month model; net-spending consistency; explained exclusions; no automatic rollover |
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
  is accepted in part; ADRs 0033–0036 are Proposed. This plan approves no
  schema, model or runtime change.
- Deterministic extraction is authoritative; the on-device model is advisory,
  RAM-gated (ADR 0009), never awaited on the capture path and never sets
  amounts, dates or references.

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
