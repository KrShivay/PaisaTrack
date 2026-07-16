# Future Development Board

Only unfinished delivery work is retained here. Completed work and the current
review queue are intentionally omitted; Git history is the archive.

## In Progress

<!-- empty -->

## Ready

<!-- Promote one dependency-ready backlog task here before implementation. -->

## In Review

<!-- Kept for handoff automation; intentionally empty in this future-only view. -->

## Backlog

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
