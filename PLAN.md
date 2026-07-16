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

Requirements:

- Monthly limit per spending category, with optional notification threshold.
- Show spent, refunded/reimbursed, remaining, percentage, and projected month end.
- Transfers and excluded payment sources do not consume budgets.
- Editing a budget never edits transactions.
- Initial version uses calendar months and no automatic rollover.

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
7. T-109/T-110 review fixes, then T-096 tolerant category resolution.
8. T-090..T-094 release hardening.

Identity and source management come before budgets because incorrect payees,
transfers, and account inclusion rules would make budget totals untrustworthy.

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
