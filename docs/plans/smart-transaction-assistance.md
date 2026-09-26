# Smart transaction assistance — implementation plan

Date: 2026-09-26. Status: proposed; documentation only.
Owner: product owner. Delivery tickets: T-177a–g, currently Backlog.

## Outcome

“App payment samjhe, details bhare, aur sirf doubt ho toh pooche. Ek baar
bataya toh matching payments ke liye yaad rakhe.”

Reduce repeated editing while preserving correct records. Success is fewer
manual decisions at measured accuracy, not the number of fields populated.
Do not require a description, receipt, or custom category for every payment.

## Existing foundation and actual gaps

Source review at commit `a429994f345a81814620c8b49a9953e840f6011d`:

- `lib/enrichment/categorizer.dart`: rules, local classifier, seed map, P2P
  default and fallback exist. Merchant-memory and LLM callbacks exist, but the
  production provider does not supply them. Helper tests are not evidence of
  end-to-end integration. Revalidate before implementing.
- `lib/data/repositories/category_correction.dart` and
  `transaction_repository.dart`: this-payment, future, historical and group
  scopes already exist. Extend these; do not build a parallel correction path.
- `TransactionCorrectionController`: shared correction/undo sequencing exists;
  T-157b still needs independent review. Verify full rule/feedback undo semantics.
- `DecisionPolicy`: auto/ask/review routing exists. Confidence scores must be
  validated against real confirmed outcomes before widening automation.
- Payee aliases, local classifier training, and Sort exist. Production history
  coverage, grouping and persistence need explicit acceptance evidence.

## Proposed user journey

1. **Capture:** use the same ingestion path for live SMS and imported history.
   Parse amount, currency, direction, timestamp, account and reference from
   evidence. A later statement may corroborate them; never invent absent values.
   Route reminders to expected events, never settled transactions or totals.
2. **Recognise:** resolve a known payee using exact identifiers and confirmed
   aliases. Similar names alone cannot merge people or businesses.
3. **Fill:** apply explicit user rules first, then validated confirmed-history
   memory, classifier and known merchant hints. Preserve an existing user edit.
4. **Decide per field:** clear facts need no prompt. Category uncertainty must
   not force re-confirmation of an already verified amount/date.
5. **Ask once:** “Is this your grocery shop?” with suggested existing categories,
   Change, and “Yaad nahi”. Show date, amount, account and raw payee as context.
6. **Apply with scope:** offer “This payment”, “Future matching payments”, or
   “These matching past payments + future”. Preview count, sample rows,
   exceptions and rule before bulk mutation. Default conservatively for mixed
   merchants and people. Commit correction/feedback/rule atomically; offer undo.
7. **Review exceptions:** group safe matches into one question, show unresolved
   group and transaction counts separately, and provide paging beyond 100 rows.
   An optional digest replaces repeated interruptions; default to in-app review.
8. **Learn:** only explicit confirmation/correction supplies trusted labels.
   Automatic labels, silence and skipped items are not confirmations. A corrected
   rule invalidates affected suggestions; undo removes its training influence.

“Yaad nahi” stays unresolved without recurring daily pressure: persist deferral
until new evidence or an explicit user-chosen reminder; keep it discoverable.
No “all done” state while unresolved/deferred items remain.

## Field policy

| Field | Allowed source | When unclear |
|---|---|---|
| Amount/date/currency/direction/reference | Verified source span or explicit user correction | Preserve uncertainty; request only missing fact |
| Readable payee | Exact identity, confirmed alias, source merchant text | Suggest a candidate; no automatic fuzzy merge |
| Category | User rule, confirmed history, evaluated classifier | Suggest existing categories; LLM alone never silently applies |
| Description | Template from known payee/category; explicit user text | Optional; never invent purchase items, place or purpose |
| Personal transfer purpose | Explicit source or user answer | Unknown; a person's VPA does not prove non-spending |
| Refund/own-transfer relationship | Validated linkage contract and source evidence | Keep separate; preview ambiguous links |

The current `p2p_default` transfers behavior must be evaluated in T-177b:
shopkeepers may use personal VPAs. Identity type alone must not remove genuine
expenses from spending totals. Category and accounting eligibility are separate
review concerns.

## Categories and repeat learning

- Use bundled categories first; reuse user categories by stable ID.
- Suggest a new category only for a recurring, meaningful distinction the user
  wants. Require approval; never auto-create one per merchant or model guess.
- An explicit future rule is stronger than statistical history. Resolve
  conflicting rules deterministically; expose replace/disable with preview.
- Mixed-use payees (marketplaces, friends) require transaction-specific evidence
  or a narrower user rule. Do not learn “all Amazon = Electronics”.
- Deleted/merged categories invalidate affected rules/models safely; no dangling
  category assignment. Explicit user corrections survive rescans and upgrades.

## Architecture and data contract — proposed

Keep extraction, identity, category choice and financial eligibility separate.
Reuse repositories, shared corrections, the local classifier, `FinancialCalendar`
and `FinancialEligibility`. Require query-parity tests: the current assistant
transaction query omits lifecycle and spending-category eligibility filters;
real database rows alone do not make its totals equivalent to Dashboard.
Proposed ADR 0011 owns the boundaries.

Original source evidence and extracted spans stay immutable; normalized values
can be explicitly corrected with old/new values, actor/source and edit version
retained. Each derived field needs value/candidate, source kind, source/transaction IDs,
confidence method/version, confirmed/automatic/suggested state and last edit
version. Reuse existing evidence/feedback tables where sufficient; T-177a must
produce a schema diff before choosing new tables or version numbers.

Review groups are rebuildable queries over stable identity plus compatible
suggestions, not new financial records. Store only necessary deferral/rule state.
Preview tokens bind row IDs and versions; stale previews must refresh before
write. Bulk undo restores prior values, rule state and feedback and must refuse
to overwrite a newer independent edit. Recompute dependent insights after edits.

Data retention, backup/restore and deletion must cover any new metadata. Derived
metadata is allowed; synthetic transactions or fabricated source evidence are
not. No new network permission or cloud inference is proposed.

## Delivery sequence

| Phase | Ticket | Deliverable | Exit condition |
|---|---|---|---|
| 0 | T-177a | Integration audit, evidence contract, baseline evaluation | Production call-path tests; provenance and sample-size report |
| 1 | T-177b | Safe payee/memory integration and P2P eligibility guard | Repeated confirmed labels help; ambiguity abstains; no false exclusion |
| 2 | T-177c | Reusable correction scope, rule conflict and complete undo | One correction updates previewed scope; replay and undo are safe |
| 3 | T-177d | Paged grouped review and persistent deferral | No hidden tail; restart preserves deferrals; fewer repeated questions |
| 4 | T-177e | Category reuse and evidence-only optional descriptions | Existing categories reused; no invented purpose or mandatory notes |
| 5 | T-177f | Shadow evaluation and staged opt-in release | Precision/effort/device gates met; fallback and rollback verified |
| Later | T-177g | Receipt/screenshot matching discovery | Local OCR feasibility, consent and evidence contract reviewed |

Implement one child at a time after grooming. T-176 remains the current task.
T-157b review must pass before extending corrections. Reuse T-143 shadow work
if verified; its board/brief status conflicts and must be resolved first.
T-102 statement reconciliation remains separate and is not an MVP dependency.

## Acceptance and measurement

Record the baseline before changing behavior. Proposed targets below are release
gates to validate, not claims of current accuracy or guaranteed automation:

- At least 50% fewer user decisions per 100 eligible transactions against the
  current flow on the same replay set, without lowering precision.
- At least 98% precision among audited automatic category assignments. Report
  numerator, denominator and a 95% interval; require its lower bound ≥95% before
  broad rollout. Evaluate new/repeated/mixed payees separately. Insufficient
  samples mean suggestion-only operation, not a passing result.
- Report automation coverage over all eligible transactions alongside precision;
  abstention must not hide poor coverage. Report incorrect accounting exclusions
  separately, with zero known failures in the release acceptance set.
- 100% of persisted amount/date/reference facts trace to evidence or user edits;
  no model-only source facts. Unknown facts remain unknown.
- Every bulk mutation preview/undo, concurrent edit, rule conflict, reimport,
  category deletion, process restart and missing-model scenario has a test.
- Show truthful loading/error/empty/partial states. Keyboard, large text,
  screen reader and navigation insets remain usable; reuse T-176 conventions.
- Measure p50/p95 ingest and review latency, peak model memory and battery cost
  on target hardware against the T-115 baseline. No LLM on every payment;
  ingestion must complete when optional inference is unavailable.

Synthetic fixtures can test edge cases, but real-data accuracy claims require
sanitized device/public evidence under ADR 0005, with chronological holdout.
Do not train or tune using future confirmations from the test window.

## Rollout and risk

Shadow proposals first without changing production rows or issuing prompts;
then suggestions; then opt-in automatic labels for validated cohorts. Keep a
local feature switch to disable inference while capture and explicit rules work.
Rollback stops new decisions and discards pending suggestions; it must not
silently revert confirmed edits or require downgrading a database.

GitNexus upstream planning check for `Categorizer.categorize` on 2026-09-26:
CRITICAL, 11 impacted symbols, 3 direct graph references, 5 reported affected
process groups across Capture/Enrichment. Direct references include `ingest`
and categorizer/LLM tests; transitive coverage includes backfill, expected-event
capture and onboarding. This is a planning snapshot, not permission to skip
fresh impact analysis on each future edit.

## Out of scope

Cloud analysis; background inbox/email scraping; purchasing or moving money;
merchant identity guesses presented as facts; inferred itemized purchases;
automatically creating categories; automatic repair of missing transactions.
Receipt OCR and statement import must use explicit supplied evidence and remain
separate from this MVP.
