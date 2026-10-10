# ADR 0029 — Conservative capture correctness repairs

Status: Accepted for T-201 bounded bug fixes, 2026-10-04.

## Context

Checked-in bank fixtures reproduce payments discarded by OTP/security footer
words and failed-payment credits excluded as failed. Lifecycle-blind duplicate
matching can suppress settled retries. Processing errors are treated as terminal
at the current parser version. Numeric VPAs are currently classified as
Transfers with full confidence despite absent evidence of purpose/ownership.
Template date constructors accept invalid calendar dates by rolling them over.

## Decision

- Associate classification with the described event, preserve genuine OTP,
  future/pending, failed and reversal safeguards, and use whole-token cue
  boundaries. A credit explicitly returning a failed payment is a settled
  credit; this does not invent a refund link or net-accounting adjustment.
- Duplicate matches require compatible known lifecycle states. A settled
  payment cannot be hidden behind a failed or pending root. Retain settled
  cross-source echo behavior and source amounts.
- Share retry/terminal decisions across live ingestion, batch and catch-up.
  Processing errors remain retryable at the same version, once per presented
  message per run; preserve bounded catch-up overlap and successful-message
  idempotency. No automatic infinite retry or telemetry of message content.
  Carry failed-attempt identity evidence across pages in one import/catch-up
  run; repeated failures are never reported as successful or already known.
  Bound that evidence and stop with an incomplete result on capacity exhaustion
  rather than forget claims, retry indefinitely or stamp the scan complete.
  Count each failed identity once per run, including conflicting identity
  claims. Forced scans discard the old resume cursor, then checkpoint only
  completed pages; clearing a cursor preserves the completed-version marker.
- Increment the parser contract version for classifier/date changes. A retained
  raw row with a known older version may be replayed when re-presented, even if
  an earlier classifier marked it processed, only after excluding any existing
  transaction by ID/source ID and any disposition. Preserve legacy processed
  rows without version evidence. Same/newer terminal outcomes remain terminal;
  same-version processing errors retry once per unique ID per run. Keep parser
  and history-scan versions separate; do not trigger a full rescan implicitly.
- Numeric/person-like VPA shape alone does not establish non-spending or an
  owned transfer. Preserve explicit rules/categories; otherwise abstain and use
  the existing low-confidence fallback/review path. Do not assign a guessed
  merchant category or rewrite historical categories.
- Invalid date components return the existing receive-time fallback, never a
  silently rolled date. Validate numeric and alphabetic month paths, including
  leap years. Preserve existing date-only formats and receive-time/calendar
  resolution; do not add clock formats as part of this correction.
- Apply a matched explicit user rule's stored description only to new captures.
  Description-only actions must not claim category-rule confidence or inherit
  invented text from category models/memory. Preserve existing descriptions and
  source/user facts on replay; no historical description rewrite.
- Same-account source rows separated only by capture channel must not become
  transfer legs merely because source IDs differ. A bounded guard may reject
  equal/unknown masked identities; it must not merge sources or claim suffixes
  uniquely identify accounts. Additional automatic reconciliation and confirmed
  ownership/card contracts remain separate gates.

## Historical and delivery limits

Existing source transactions and user corrections remain immutable under these
repairs. Already suppressed or misclassified persisted transactions need an
explicit evidence-backed repair contract; parser version changes alone do not
repair them. A replay of retained non-transaction raw rows may be separately
bounded by absent transaction/disposition checks and parser-version evidence;
it must not bulk edit transaction history. Purged messages cannot be recovered
without an authorized inbox re-import.

No schema, backup format, refund-period decision, source merge or suggestion
rollout changes. Meaningful regression-first tests, complete graph review and
full verification are required. Reverting the relevant scoped commit restores
prior capture behavior without deleting source rows.
