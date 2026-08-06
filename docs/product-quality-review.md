# Product-quality review cadence

This is the recurring release-candidate procedure created by T-172g. It is
local-first and analytics-free: the review produces files and test evidence,
not event telemetry or uploaded financial data.

Current gate status: **CLOSED WITH WAIVER** for LUNA-07/T-172e. On 2026-08-01,
the product owner explicitly marked external participant and interactive TalkBack/
accessibility evidence not required for this review; device smoke evidence
remains an observation and no further T-172e pickup is planned.

## Baseline package

At each release candidate, copy the prior package and update:

1. `test/fixtures/product_review/corpus.json` and its schema version.
2. The execution register in `docs/product-value-review-2026-08.md`.
3. The P0/P1/P2 scorecard and decision changes.
4. The manual QA matrix below.
5. `docs/product-status.md` with remaining release blockers.

Keep only the latest three handoff notes in `WORKLOG.md`; archive superseded
review packages under `docs/archive/reviews/` with the release date.

## Cadence and gates

| When | Rerun | Required evidence | Gate |
|---|---|---|---|
| Every PR touching transaction/capture/analytics/privacy | Focused corpus assertions, impacted unit/widget tests, `git diff --check` | Changed-scope note and privacy assertion | No P0 trust regression or unreviewed data disclosure |
| Weekly during active product work | Full corpus, scorecard, source inventory delta | Prior/current counts and changed priorities | New capability has entry point, data rule, error state, privacy constraint and test |
| Release candidate | Full Flutter suite, analyze, Android unit tests, corpus, UI semantics/responsive matrix, backup/reset audit | Artifact paths, pass/fail, known pre-existing failures, device/build details | No unbounded capture loss, plausible partial totals, silent key rotation, or incomplete reset |
| Before a feature proposal | User-job review, competitor/standards refresh, 5–7 moderated scenarios | Anonymized task metrics and explicit evidence limitations | Proposal must beat an existing P0/P1 trust gap or explain why it does not |

## Manual QA matrix

Run on a small Android device with gesture navigation and one wider device:

| Area | Conditions | Check |
|---|---|---|
| Onboarding/capture | fresh install; permission granted, denied, permanently denied; resume | State is truthful, retry is bounded, no raw body appears in status/error |
| Activity | 1k rows; identical timestamps; search old row; filters; inserted row between pages | No duplicate/gap; old match appears; cursor and filters persist |
| Dashboard | empty, sparse, typical, aggregate error, period boundary | Loading/error is distinct from zero; totals disclose eligibility and period |
| Detail/correction | low trust, duplicate, transfer, refund, pending, reversed; undo | Evidence retained; explanation matches totals; scope preview/undo works |
| Review/notifications | empty, one item, many items, notification denied | Actions are labelled, state persists, no optimistic completion |
| Trends/recurring | no history, active, missed, price changed, settled | State and eligibility are explained; no future event is counted as settled spend |
| Backup/export/delete | cancel, wrong passphrase, valid round-trip, reset | Explicit confirmation; no plaintext temp artifact; post-reset DB/files/cache audit |
| Accessibility | 1.5× and 2× text; TalkBack; narrow/wide; keyboard open; landscape | Focus order, labels, selected state, exposed touch target ≥48dp, no inset overlap |

## Comparison record

For every rerun, add a compact table to the release archive:

| Metric | Prior | Current | Threshold | Result |
|---|---:|---:|---:|---|
| Corpus records reachable | — | — | 100% | — |
| Page duplicates/gaps | — | — | 0 / 0 | — |
| Aggregate parity cases | — | — | 100% | — |
| Capture outcome uniqueness | — | — | 100% | — |
| Raw-content leakage checks | — | — | 0 | — |
| Primary actions labelled | — | — | 100% | — |
| Primary actions ≥48dp | — | — | 100% | — |
| Human/device scenarios passed | — | — | 100% or explicitly waived | — |

An unchanged result is still evidence only if the same corpus version and test
commands are recorded. A changed corpus requires a note explaining why the
baseline moved. A release candidate may clear the human/device evidence gate
only with an explicitly recorded external session or product-owner waiver. This
review uses the latter and must retain the waiver in its archive.
