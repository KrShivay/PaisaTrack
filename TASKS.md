# Future Development Board

Only unfinished delivery work is retained here. Completed work and the current
review queue are intentionally omitted; Git history is the archive.

## In Progress

<!-- empty -->

## Ready

<!-- Promote one dependency-ready backlog task here before implementation. -->

## In Review

<!-- Kept for handoff automation; intentionally empty in this future-only view. -->

## In Review

### Device-test blocker fixes (2026-07-17; implemented by @claude, need QA)

- [ ] T-111 [S0/S1] payment_sources v6 repair migration.
      Fixed: schema bumped to v6 with `_repairPaymentSourcesV6` that backfills
      NULLs and rescales millisecond datetimes in existing rows and drops/
      recreates the source trigger to write seconds; v5 backfill/trigger now
      write seconds + is_active. Regression fixture added
      (`app_database_v6_payment_source_repair_test.dart`). Resolves the
      unusable Transactions and Accounts screens without clearing app data.
      QA: install over the affected v5 DB and confirm both screens load.
- [ ] T-112 [S1] Assistant single-token category matching.
      Fixed: `AssistantIntentClassifier._matchCategory` resolves an unambiguous
      token like "food" to "Food & Dining"; shared tokens fail closed. Test
      added. QA: "How much did I spend on food this month?" returns the same
      total the dashboard shows.
- [ ] T-113 [S1] Denied-SMS lockout.
      Fixed: `continueWithoutSmsProvider` lets a user who declines enter
      HomeShell (manual entry + Settings reachable) with a persistent
      permission banner on the dashboard; onboarding offers "Continue without
      SMS access". Tests added. QA: deny permission, confirm the app is usable
      and permission can be granted later from the banner/Settings.
- [ ] T-114 [S2/S3] Accessibility/error-handling fixes.
      Fixed: Categories FAB tooltip; large-text stat cards wrap labels and
      scale amounts (no ellipsized "vs previous month"/projected); Accounts
      screen now logs the raw error and shows a safe retry instead of a bare
      exception. QA: 1.5x font on dashboard; unlabeled-FAB check.

## Backlog

### Remaining device-test follow-ups (2026-07-17)

- [ ] T-115 (@codex) [S2] Profile startup and memory on a release/profile build.
      Debug-build samples showed ~3.05s cold launch and 421–423 MB PSS baseline
      rising to ~533 MB after navigation. Not a proven leak, but high.
      AC: repeat with a signed profile/release APK; profile the embedded model,
      GPU buffers, and native caches; record evidence toward T-092.
- [ ] T-116 (@codex) [S3] Scale the Review backlog UI.
      6,807 review rows across 2,467 merchants with only an "All" list.
      AC: merchant/category grouping, search, filters, and merchant-level bulk
      review/confirm. (Complements T-106's inflow fix.)
- [ ] T-117 (@codex) [S3] Scale the Payee Labels screen.
      Large raw-identity list has no search/filter.
      AC: search, merchant grouping, unresolved-only filter, and duplicate
      suggestions.
- [ ] T-118 (@codex) [S3] Recurring empty-state diagnostics.
      The screen promises detection after three matching transactions but never
      explains why none qualify.
      AC: show per-merchant eligibility/progress and fragmented-merchant
      warnings instead of a bare empty state.
- [ ] T-119 (@codex) [S3] Category action menu backdrop.
      The popup darkens almost the whole screen, obscuring context.
      AC: reduce backdrop emphasis or switch to a contextual bottom sheet.
- [ ] T-120 (@codex) [S2] Large-text and semantics widget-test coverage.
      AC: golden/widget tests at 1.5x font for the dashboard stat cards and a
      semantics test asserting labeled controls (FABs, icon buttons).

### Remaining code-review fixes
- [ ] T-108 (@codex) [P2] Capture coverage for major banks.
      SmsFilter allowlists ~26 sender tokens and templates cover 6 banks;
      HDFC/ICICI rely entirely on the 0.5–0.6-confidence generic parser and
      unlisted banks capture nothing, invisibly.
      AC: add sanitized-fixture templates for HDFC and ICICI, extend the
      sender allowlist, and surface "sender not recognized" counts in the dev
      screen so gaps are measurable.
- [ ] T-109 (@codex) [P3] Correction-rule matching semantics.
      `existingAndFuture` loads all rows and filters in Dart, and merchant
      matching uses substring `contains` which over-matches (e.g. an "Amazon"
      rule hits "Amazon Pay Later").
      AC: SQL-side target selection with exact/normalized-prefix semantics and
      tests for near-name merchants.
- [ ] T-110 (@codex) [P4] Backup completeness and passphrase floor.
      Export omits baselines, insights, model_meta, and recurring_series, so
      adaptive thresholds and trust-ledger state silently reset on restore;
      no minimum passphrase strength is enforced.
      AC: include or explicitly document excluded tables; enforce a minimum
      passphrase length in the export UI.

### Device acceptance

- [ ] T-103 (@codex) [P1/QA] Validate responsive startup on the target device.
      Implemented: shell-first startup, deferred WorkManager setup, immediate
      progress UI, delayed history import, and yielding between imported rows.
      AC: cold open remains interactive during initial load and records evidence
      toward T-092's <2s cold-start budget.
- [ ] T-104 (@codex) [P1/QA] Validate live and resume SMS ingestion on-device.
      Implemented: EventChannel live ingestion plus newest-first incremental
      catch-up with bounded recent-gap recovery; no automatic full rescan.
      AC: a real incoming transaction appears without manual re-import, and SMS
      received while stopped is caught up after resume/open without UI stalls.

### Identity and data quality

- [ ] T-102 (@codex) [P2] Local statement import and reconciliation.
      AC: preview and idempotently import CSV statements, reconcile safely against SMS/manual rows, and summarize matched/imported/ambiguous/rejected rows.
- [ ] T-096 (@codex) [P2/P3] Tolerant free-text category resolution.
      AC: common typos resolve safely; ambiguous matches refuse instead of silently selecting a category.

### Planning and commitments

- [ ] T-100 (@codex) [P2] Reimbursement, refund, and reversal tracking.
      AC: link full/partial repayments to original expenses and use explained net amounts in spending and budgets.
- [ ] T-101 (@codex) [P3] Recurring-payment calendar and upcoming-message detection.
      AC: combine detected series with bill-due/autopay SMS, keep expected events separate from settled transactions, and match later debits safely.
- [ ] T-098 (@codex) [P3] Monthly category budgets.
      Depends: T-100
      AC: calendar-month limits show spent, net refunds/reimbursements, remaining, threshold state, and projected month end while excluding transfers and excluded sources.

### Release hardening

- [ ] T-090 (@codex) [P5] App lock.
      AC: protect launch/resume with safe recovery and unavailable-biometric paths without weakening encrypted storage.
- [ ] T-091 (@codex) [P5] Privacy-safe home widget.
      Depends: T-090
      AC: configurable summary reveals no raw SMS or sensitive detail while the device/app is locked.
- [ ] T-092 (@codex) [P5] Performance budgets.
      AC: measure and meet cold start <2 seconds and 10,000-message import <60 seconds on the target device.
- [ ] T-093 (@codex) [P5] Accessibility and onboarding acceptance.
      AC: TalkBack, contrast, large text, touch targets, light/dark themes, and unaided onboarding pass on-device.
- [ ] T-094 (@codex) [P5] Distribution and portfolio release package.
      Depends: T-090, T-092, T-093
      AC: signed release path, SMS-permission declaration or maintained sideload page, screenshots, privacy/architecture story, checklist, and rollback notes.

## Board rules

- Keep only unfinished work.
- Move at most one implementation task to `In Progress`.
- `In Review` is temporary; remove reviewed tasks instead of retaining a Done log.
- Record durable decisions in ADRs and use Git history for completed evidence.
