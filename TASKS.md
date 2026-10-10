# Future Development Board

Only unfinished work belongs here. One line per task; detail, evidence and
subtask briefs live in `docs/tasks/<id>.md`. Current state:
`docs/product-status.md`. Order, waves and file locks:
[roadmap](docs/plans/roadmap.md). Completed evidence: Git history.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening. Sizes: ~S Haiku-sized (<½ day), ~M Sonnet-sized (≤1 day).
Subtask ids suffix the parent (T-203a). Parents are containers; claim a child.

## In Progress

- [ ] T-201 [P0] Verify and repair reported transaction-integrity defects.
      Paused at owner request; capture fixes are uncommitted on the owner
      machine (153 focused tests). Post-fix physical verification open.
      [T-201](docs/tasks/T-201.md).

## Ready

<!-- Groomed parents with claimable children. "Now:" children have no unmet
     dependency; the rest follow the Depends line in the brief. Respect the
     roadmap's hot-file locks when running children in parallel. -->

- [ ] T-203 [P0] Import flicker and speed. Root cause: Dashboard aggregates
      watch `transactionListProvider` and `.when` shows skeletons on reload.
      Now: a, b, d, e. Then c, f, g2–g5b (parallel Haiku), g6, h, i.
      [T-203](docs/tasks/T-203.md).
- [ ] T-205 [P0] Categorisation and income gap (~96% "Other"). Now: a
      (counts-only diagnostics), b (cue engine). Then c, d. e–h after ADR 0036
      is accepted. [Plan](docs/plans/categorisation-v2.md), [T-205](docs/tasks/T-205.md).
- [ ] T-210 [P1] Test-suite speed (~15 min). Now: a, c1, d. Then b, g1,
      c2–c5 (parallel Haiku), e/f, g2, h. Never weaken assertions.
      [T-210](docs/tasks/T-210.md).
- [ ] T-204 [P1] UI/UX v2 and icon system. Now (foundations): a, c, d, e, i,
      m, o. Then b, f, g, h, j, k, l; per-folder screen work (n–al) after
      T-203's change to the same folder. [Plan](docs/plans/ux-v2.md),
      [T-204](docs/tasks/T-204.md).
- [ ] T-208 [P1] Performance budgets and host proxies. Now: a, e, h, l. Then
      b, d, j1; c; f (after T-203e); g, i, j2, k.
      [Plan](docs/plans/performance.md), [T-208](docs/tasks/T-208.md).
- [ ] T-207 [P1] Intelligence v2, no-schema phase. Now: a, b, c, d, e. Then
      f, ag; g, h, i. Schema children (j onward) wait for ADR 0034/0035.
      [Plan](docs/plans/intelligence-v2.md), [T-207](docs/tasks/T-207.md).
- [ ] T-211 [P1] Comprehensive category taxonomy (35 top / ≤300 sub). Now: a
      (trim draft). Then c; b/e after ADR 0036; d.
      [T-211](docs/tasks/T-211.md).
- [ ] T-162b [P1] Sender-onboarding evidence format and allowlist review gate.
      Now: b1. Then b2. [T-162](docs/tasks/T-162.md).
- [ ] T-171b [P2] Publish performance/accessibility acceptance budgets. Now:
      b1, b2a. Then b2b, b2c, b3 (after T-208l), b4. [T-171](docs/tasks/T-171.md).
- [ ] T-206 [P1] Merge the integration branch to `main` (PR) and hand the
      owner the remote-branch deletion list (session proxy cannot delete).
      [T-206](docs/tasks/T-206.md).

## In Review

<!-- Host-verified work awaiting device/owner gates; evidence in each brief. -->

- [ ] T-202 [P0] Owner 12-item batch (schema v20, ADR 0032) host-verified.
      Open: physical-device QA (sheets/edge-to-edge, toasts, AI download,
      dashboard), Sort list account/channel hint.
- [ ] T-200 [P0] Unified detail confirmation; phone acceptance open.
      [T-200](docs/tasks/T-200.md).
- [ ] T-199 [P1] Static UPI QR; Sort card/list device QA open.
      [T-199](docs/tasks/T-199.md), ADR 0023.
- [ ] T-167j [P0] App-wide back contract; API 36 device gate open.
      [T-167j](docs/tasks/T-167j.md).
- [ ] T-176 [P1] Global bottom-inset contract; landscape, three-button and
      remaining-route physical checks open. [T-176](docs/tasks/T-176.md).
- [ ] T-167c [P1] Large-text overflow fixes; physical-device acceptance open.
      [T-167c](docs/tasks/T-167c.md).
- [ ] T-194 [P1] Compressed ARM64 APK trial; candidate install, storage and
      cold-start measurement open. [T-194](docs/tasks/T-194.md).
- [ ] T-177a [P1] Production integration audit; owner holdout period,
      thresholds and live/resume device gates open.
      [Evidence](docs/tasks/T-177a-evidence.md), [T-177](docs/tasks/T-177.md).
- [ ] T-154b [P2] Sort inline corrections; owner-phone check open.
      [T-154](docs/tasks/T-154.md).
- [ ] T-198 [P1] Readable payee names; owner-phone check open.
      [T-198](docs/tasks/T-198.md).
- [ ] T-197 [P1] Activity scroll retention after edit; owner-phone check
      open. [T-197](docs/tasks/T-197.md).
- [ ] T-196 [P1] Transaction details card; owner-phone check open.
      [T-196](docs/tasks/T-196.md).

## Backlog

### Blocked on an owner decision (see WORKLOG questions)

- [ ] T-209 [P1] Refund attribution default (purchase vs posting period);
      blocks T-100b/c. Window decided: 31-day lookback, 3–5 business days.
- [ ] T-165c [P1] Integer minor-unit money; 16 children after ADR 0033 is
      accepted. Recommended before T-100c/T-190f/T-098.
      [T-165c](docs/tasks/T-165c.md).
- [ ] T-100 [P2] Refund/reimbursement links and net totals; a2/b1a ready
      after T-209; b1b–c5 follow. [T-100](docs/tasks/T-100.md).
- [ ] T-190 [P2] Credit-card accounting; re-split slices await ADR 0020 and
      card decisions 2–6, 8. [T-190](docs/tasks/T-190.md),
      [plan](docs/plans/credit-card-accounting.md).
- [ ] T-098 [P3] Monthly category budgets; after T-165c and T-100c1.
      [T-098](docs/tasks/T-098.md).
- [ ] T-207 schema phase (j–am) after ADR 0034/0035 acceptance.

### Planned, groomed briefs

- [ ] T-162d [P2] Payroll alias recognition after T-205b/c/e.
      [T-162](docs/tasks/T-162.md).
- [ ] T-170d [P2] Manual QA matrix for senders/templates, unsupported-sender
      telemetry and false-positive privacy checks. [T-170](docs/tasks/T-170.md).
- [ ] T-177g [P3] Local receipt/screenshot matching feasibility (spikes
      only). [T-177](docs/tasks/T-177.md).
- [ ] T-130 [P2] Residual architectural coupling (import-cycle map, seams).
      [T-130](docs/tasks/T-130.md).
- [ ] T-178b [P1] Forecast range validation and backtesting; T-178c Hinglish
      intents and T-178d evaluation follow. [T-178](docs/tasks/T-178.md),
      [plan](docs/plans/grounded-ai-validation.md).
- [ ] T-102 [P2] Local statement import and reconciliation.
      [T-102](docs/tasks/T-102.md).
- [ ] T-101 [P3] Expected-payment calendar gaps (reuse T-138 pipeline).
      [T-101](docs/tasks/T-101.md).
- [ ] T-177b–f [P1] Smart assistance: identity memory, correction scopes,
      grouped review, category reuse, staged release; gated on T-177a.
      [T-177](docs/tasks/T-177.md).

### Scale, reliability, accessibility and release

- [ ] T-115 [P1] Device profiling: cold start, 10k import, model PSS (feeds
      T-208l).
- [ ] T-165a [P1] 10k/50k Activity query/render profiling (host part is
      T-208a/d). T-165d [P2] split `TransactionRepository`.
- [ ] T-164b [P1] Activity filter/search in SQL; T-164c [P1] visibility
      flags; T-164d [P2] "show excluded" filter.
- [ ] T-160d [P1] Reusable paged-list controller. T-161e [P1] scan-outcome
      end-to-end tests. T-162c [P1] unsupported-sender counts (no PII).
      T-163a/b capture-status component, scan cancel/resume.
- [ ] T-166a [P1] Salary income card; T-166b [P2] income-source correction.
- [ ] T-170a [P0] Fault-injection tests; T-170b [P1] ADR 0021 device
      retention proof; T-170c [P1] release-build smoke tests.
- [ ] T-171a [P1] CI shards (consumes T-210f/h).
- [ ] T-128 [P1] Accessibility and failure-state coverage; T-167d–i semantic
      controls, FAB/inset audits, goldens, sheet action bars (coordinate with
      T-204).
- [ ] T-168a/c/d detail helpers, Bloom sheet routing, golden suite (coordinate
      with T-204m). T-169a import progress model (superseded by T-203e if it
      lands first); T-169b data-footprint screen.
- [ ] T-118 [P2] Explain recurring ineligibility. T-096 [P3] tolerant
      category text resolution.
- [ ] T-090 [P4] App lock → T-091 [P4] privacy-safe widget → T-094 [P5]
      distribution package.
- [ ] Product-value follow-ons PV-01, PV-03…PV-08 (contracts in
      [T-172](docs/tasks/T-172.md)).

### Older UI/refactor children (briefs in `docs/tasks/`)

- T-133a/b quarantine store and retry; T-151b/d/e Ask states and inline charts
  (coordinate with T-207ac/ae); T-149a–c local profile; T-156c, T-158b/c,
  T-159c detail-screen split and behavioural tests (T-204z/aa depend on
  T-158c). Completed groups: [archive](docs/archive/planning-cleanup-2026-09.md).

## Board rules

- Keep exactly one instance of every `##` workflow heading; handoff automation
  parses them literally.
- Keep only unfinished work, one short line per task; evidence goes in the
  brief. Remove an item after implementation and required verification.
- Run several children in parallel only when they own disjoint files and the
  roadmap's hot-file locks allow it; at most one schema-changing child at a
  time.
- `In Review` is temporary and contains only unresolved verification/review.
- Record current state in `docs/product-status.md`, durable decisions in ADRs,
  and completed evidence in Git history or `docs/archive/`.
