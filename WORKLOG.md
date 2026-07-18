# Current Handoff

This is a rolling handoff, not an append-only project history. Keep only the
latest three development entries; Git history retains older evidence.

## 2026-07-17 — Device-test blocker fixes (@claude)

- S0/S1 payment_sources crash: bumped schema to v6 with a non-destructive
  repair (`_repairPaymentSourcesV6`) that backfills NULLs, rescales millisecond
  datetimes, and drops/recreates the source trigger; the v5 backfill and
  trigger now write seconds and `is_active`. Regression fixture added
  (`app_database_v6_payment_source_repair_test.dart`). Fixes the unusable
  Transactions and Accounts screens without clearing data.
- S1 assistant: `_matchCategory` resolves single distinctive tokens ("food" →
  "Food & Dining") and fails closed on shared tokens; test added.
- S1 lockout: `continueWithoutSmsProvider` routes a declining user into
  HomeShell with a persistent dashboard permission banner; onboarding gained a
  "Continue without SMS access" action; tests added.
- S2/S3: Categories FAB tooltip; large-text stat cards wrap labels and scale
  amounts; Accounts screen logs the raw error and shows a safe retry.
- Filed fixes as T-111..T-114 (In Review, need device QA) and remaining
  follow-ups T-115..T-120 (profiling, review/label scaling, recurring
  diagnostics, menu backdrop, large-text tests).
- Not runnable here: the bundled Flutter SDK is macOS-only, so `flutter
  analyze`/tests and device QA must run on the developer machine.

## 2026-07-16 — Independent code review of the full application (@claude)

- Reviewed all of lib/ and the Android capture/keystore code. Core verdict:
  architecture, privacy handling, and test discipline are sound; defects are
  concentrated in the new incremental catch-up, decision policy, and unbounded
  query patterns.
- Filed groomed fixes as T-105..T-110 in `TASKS.md`. T-104 device QA now
  depends on T-105 (catch-up StateError on empty/single-page inboxes,
  dead-process SMS drop); T-103 depends on T-107 (bounded queries).
- Deleted `PROJECT_STATUS_REPORT.md` (unreferenced; duplicated README and
  TASKS.md content).

## 2026-07-16 — T-105, T-106, and T-107 correctness/scale fixes

- Incremental catch-up now handles null terminal cursors and scans a bounded
  overlap beyond the first known SMS to recover recent live-ingest gaps.
- Seen VPA counterparties can auto-classify through the normal confidence
  policy; unseen VPAs still fail closed, and generic parsing no longer extracts
  ordinary email addresses as VPAs.
- Imports commit once per inbox page; known-id reads select identifiers only;
  ask/familiarity counts and dashboard aggregates run in SQL; transaction feeds
  page in 100-row increments with a six-row dashboard query.

## Verification

- 2026-07-16 (pre-device): `flutter analyze --no-pub` clean; full suite
  357/357; focused T-105..T-107 suite 52/52; `git diff --check` clean.
- 2026-07-17 device-test fixes: NOT verified in-session — the bundled Flutter
  SDK is macOS-only and cannot run in this Linux workspace. Before commit, run
  on the developer machine: `flutter analyze --no-pub`; the new
  `app_database_v6_payment_source_repair_test.dart`, assistant classifier, and
  onboarding tests; the full suite; and re-run device QA for T-111..T-114.

## Next action

Verify and QA T-111..T-114 on device (payment_sources repair, assistant
category, denied-permission routing, accessibility). Then resume T-108 and the
T-115..T-120 follow-ups.
