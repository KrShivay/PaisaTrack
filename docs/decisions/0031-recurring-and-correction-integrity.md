# ADR 0031 — Recurring projections and guarded category correction

Status: Accepted for T-201 bug fixes, 2026-10-04.

## Context

Dashboard commitments reuse a three-row display list and count income. Ask's
upcoming-payment query omits lifecycle/type eligibility. Foreground recurring
upsert bypasses the complete projection cleanup used nightly. Detail's category
chip bypasses existing atomic correction Undo; the repository's Undo itself can
overwrite later category/status edits.

## Decision

- Preserve the established commitment eligibility: active series, non-income,
  explicit INR for INR budget totals. Totals read all eligible rows in the
  current calendar month; presentation may take the next three. Upcoming
  payments use the same active expense semantics and preserve currency buckets.
  Disabled, cancelled, paused, muted and unknown statuses abstain. This does not
  monthly-normalize amounts or change the existing next-due-date contract.
- Share the complete recurring projection rebuild between foreground and
  nightly paths without creating another scheduler. Preserve user-controlled
  RecurringStatusMemory across changed IDs and temporary non-detection. Prune
  only detector-derived series absent from a complete successful detection;
  retain source transactions and keep persistence atomic where practical.
  Re-read current status memory and row intent in the final reconciliation
  transaction; a user change during awaited detection must survive. Keep costly
  detection outside the persistence transaction, and do not claim the entire
  detection pass is one atomic write boundary.
- Both category entry paths use the shared correction receipt. Undo validates
  every affected row against its recorded post-correction state before any
  rule, feedback or row mutation; a conflict leaves the whole operation intact.
  Restore nullable category and original status, remove only receipt-owned
  feedback and restore guarded rules. Preserve later edits and source fields.
  Refresh the displayed category cache without reseeding unsaved notes.
  Record relevant feedback membership and receipt-owned feedback values in the
  transient receipt: second-resolution timestamps alone cannot distinguish
  same-second edits that return to the same category/status. Later relevant
  feedback or changed/missing receipt evidence blocks the whole Undo. Restore
  description only if this correction explicitly changed it; other later notes
  remain untouched.
  Rule replacement creates a fresh opaque rule ID and records the exact written
  ID set in the transient receipt. Undo requires that generation and its content
  to remain owned; same-value writes within one stored second cannot share an
  ownership token. Restore the exact prior mapping from its snapshot. Legacy
  mutation tokens without generation evidence abstain; no schema is added.
- Expected-event reconciliation includes snoozed rows at their rescheduled
  date, retaining exact identity/currency/amount/window and one-payment guards.
  Missing identity or invalid amount remains unresolved; never infer missed or
  fulfilled from unsupported evidence. State updates compare the original
  eligible state so cancellation is protected. No amount-only/fuzzy match.

## Boundaries and verification

No schema, ownership confirmation, card/refund financial behavior, historical
source rewrite or suggestion rollout. Category/recurring/expected records remain
local. Regressions must cover more than three commitments, income and disabled
states, date/currency boundaries, both nullable/non-null Undo paths, feedback,
conflict abstention, unsaved notes, changed earliest recurring transactions,
remembered statuses and ambiguous expected matches. Full suite and relevant
timezone checks plus impact and complete graph review precede delivery.
