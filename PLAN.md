# PaisaTrack — Future Development Plan

This document contains only information needed for future development. Current
implementation details belong in `docs/`; completed work remains available in
Git history.

## Product direction

PaisaTrack should turn noisy financial messages and imported statements into a
trustworthy, user-correctable view of spending. It is not intended to become a
bank, payment app, investment platform, or cloud financial-data service.

## Non-negotiable constraints

- Local-first: financial data and inference stay on-device.
- Preserve evidence: labels and reconciliation never overwrite original sender,
  UPI ID, merchant text, reference, or imported statement fields.
- User control: identity merges, historical relabeling, and reconciliation are
  previewed and reversible where practical.
- Fail closed: uncertain matches remain separate or enter review.
- Spending semantics: transfers are excluded; linked refunds and reimbursements
  reduce the appropriate expense without being silently deleted.
- Schema changes are additive and migration-tested.
- No paid or proprietary runtime dependency is required for core behavior.

## Selected roadmap

### 1. Statement import and reconciliation — T-102

Import bank/card statements locally to recover missing transactions and verify
SMS-derived rows.

Requirements:

- Start with CSV plus explicit per-bank column mappings; add formats only with
  sanitized fixtures.
- Preview parsed rows and selected account before writing.
- Match by reference first, then guarded amount/date/direction rules.
- Import is idempotent and never duplicates or overwrites edited transactions.
- Unmatched rows may create statement-sourced transactions; ambiguous rows enter
  review.
- Produce a reconciliation summary: matched, imported, ambiguous, and rejected.
- Raw statement files are not retained after import unless the user explicitly
  exports them.

### 2. Reimbursement and refund tracking — T-100

Link refunds, reimbursements, charge reversals, and repayments to their original
expense.

Requirements:

- Support full and partial links and many repayments against one expense.
- Distinguish merchant refund, personal reimbursement, and correction/reversal.
- Budget and spending totals use the net linked amount for the relevant period.
- Keep both transactions visible with an explanation of the relationship.
- Suggest high-confidence links; require confirmation for ambiguous matches.

### 3. Recurring-payment calendar and upcoming messages — T-101

Turn detected recurring series and bill-due/autopay messages into a calendar of
expected payments.

Requirements:

- Combine historical recurrence detection with future-event SMS parsing.
- A due/reminder message creates an expected event, never a settled transaction.
- Match the later debit to the expected event and preserve both sources.
- Show expected date/range, amount/range, cadence, confidence, and source.
- Support reminders, snooze, cancellation, missed events, and price changes.
- Deduplicate repeated reminders for the same obligation.

### 4. Monthly category budgets — T-098

Add a planning layer over trustworthy spending totals.

The current global monthly-budget and merchant-cap prototype is not this
feature. It stores overall values in `baselines`, has no per-category/month
model, and must not be treated as completed T-098 work.

Requirements:

- Monthly limit per spending category, with optional notification threshold.
- Show spent, refunded/reimbursed, remaining, percentage, and projected month end.
- Transfers and excluded payment sources do not consume budgets.
- Editing a budget never edits transactions.
- Initial version uses calendar months and no automatic rollover.

## Rework plans

Two design documents now sit ahead of the roadmap above; both are decomposed
into PR-sized task briefs under `docs/tasks/` with a one-line index in
`TASKS.md`.

- `docs/sms-intelligence-design.md` — capture, parsing, identity, lifecycle, and
  the net-spending contract (T-131…T-144). Closes T-100 and T-101 on completion
  and supplies the shared spending definition T-098 depends on.
- `docs/ui-gaps-and-redesign.md` — conformance with the accepted Bloom handoff
  plus reported UI defects (T-145…T-154).

## Existing implementation backlog

- T-090: app lock.
- T-091: privacy-safe home widget.
- T-092: cold-start and 10,000-message import performance budgets.
- T-093: accessibility and onboarding acceptance.
- T-094: distribution and portfolio release package.
- T-096: typo-tolerant category-name resolution.
- T-103/T-104: physical-device acceptance for responsive startup and automatic
  live/resume SMS ingestion.
- T-108..T-110: bank capture coverage, correction-rule matching semantics, and
  backup completeness (see TASKS.md).

## Recommended delivery order

1. T-103/T-104 physical-device startup and SMS acceptance.
2. T-108 bank capture coverage.
3. T-102 statement import and reconciliation.
4. T-100 reimbursement/refund links.
5. T-101 recurring calendar and upcoming-message parsing.
6. T-098 monthly category budgets.
7. T-121..T-130 correctness, recovery, scale, accessibility, and release
   blockers from the verified product audit.
8. T-096 tolerant category resolution, then remaining T-090..T-094 hardening.

Identity and source management come before budgets because incorrect payees,
transfers, and account inclusion rules would make budget totals untrustworthy.

## Open decisions

High-priority product decisions that the rework depends on. **Each has a default
already applied**, so none of them blocks implementation — the plan proceeds on
the default and the decision only changes behaviour if made before the "decide
by" task ships. Nothing here is a gate.

| # | Decision | Default in effect | Decide by | Cost of changing later |
|---|---|---|---|---|
| 1 | Do pending card authorisations count in the headline monthly total? | **No** — excluded; shown only in an explicitly-labelled "including pending" view, never in budgets | T-132c | Low — a display predicate and a setting |
| 2 | Is a credit-card bill payment shown as an excluded transfer, or hidden entirely? | **Shown, excluded, with an explanation** — counting both the bill and the card's purchases double-counts | T-135c | Low — copy and one predicate |
| 3 | How long are quarantined (unreadable) messages kept? | **30 days**, matching `raw_sms` retention | T-133a | Medium — a template written on day 40 cannot retry a message purged on day 30. A content-free fingerprint kept longer would let the app say "we now support 14 messages we previously missed" |
| 4 | How are non-INR transactions treated? | **Captured with their currency, never converted**, excluded from INR totals with a visible marker | T-135a | Low — conversion needs rates, which needs a network call, which ADR 0002 forbids. Manual per-transaction rate entry is the only offline-honest alternative |
| 5 | Does skip in Sort persist across app restarts, or reset? | **Persists** through process death within the session; resets on a new day | T-153c | Low — provider storage choice |
| 6 | Which on-device model backs span location and inference? | **Qwen3-0.6B mixed-INT4** (ADR 0009) | T-115 profiling | Medium — Gemma 3 270M is worth benchmarking against the 421–533 MB PSS problem; span location is a much easier task than structured extraction, so a smaller model may suffice |
| 7 | What confidence auto-links a refund to its original expense? | **0.90**, with undo | T-135b | Low — a threshold in `feature_flags`, tunable from T-143 metrics without a rebuild |
| 8 | Is the profile display name required? | **Optional** — blank falls back to a neutral greeting, never "Hey ," | T-149a | Low |

Two of these are worth an early answer because the cost of reversing them grows:
**#3** (retention shapes what can ever be recovered) and **#6** (model choice
shapes the memory budget the whole app is measured against).

Everything else can be decided when its task is claimed, or left on the default
indefinitely.

## Definition of done

Every task requires:

- pre-edit GitNexus impact analysis;
- tests for behavior, migration, failure, and idempotency paths;
- documentation updates for architecture, schema, privacy, and manual QA;
- `flutter analyze`, relevant focused tests, full Flutter tests, Android tests
  when native code changes, `git diff --check`, and `detect_changes()`;
- physical-device evidence when behavior depends on SMS, storage pickers,
  background work, local models, performance, or accessibility.

## Legacy ADR reference map

Older ADRs may cite sections from the original build plan. Use these current
sources instead:

- legacy §1 principles → this document's non-negotiable constraints;
- legacy §2 stack → `pubspec.yaml`, Android build files, and model ADRs;
- legacy §6.2 record/schema → `NormalizedTransactionRecord` and `docs/schema.md`;
- legacy §7.3–§7.8 intelligence → `docs/architecture.md`;
- legacy §8 privacy → `docs/privacy.md`.
