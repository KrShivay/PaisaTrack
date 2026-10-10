# Current Handoff

## 2026-10-10 — Planning batch: plans, briefs, board slimming (T-207/T-205/T-208/T-204/T-210 …)

- Docs-only session on `claude/paisatrack-multi-feature-mh2nhw` (no lib/test
  behaviour change; one comment-only fix in `app_tokens.dart`). No Flutter or
  device checks run; doc links, `git diff --check` and GitNexus
  detect-changes (docs sections only, 0 processes) pass.
- New plans: [intelligence-v2](docs/plans/intelligence-v2.md),
  [categorisation-v2](docs/plans/categorisation-v2.md),
  [performance](docs/plans/performance.md), [ux-v2](docs/plans/ux-v2.md).
  Briefs with 1–3-file children, model sizing, parallel groups: T-203, T-204,
  T-205, T-206, T-207, T-208, T-210, T-211, T-165c, T-170, T-171; refreshed
  T-098, T-100, T-130, T-162, T-177 (g), T-178 (b), T-190. Proposed ADRs
  0033 (minor-unit money), 0034 (SMS facts, narrow retention amendment),
  0035 (dashboard layout), 0036 (payee decisions, cue rules; no schema).
- Key findings: flicker = Dashboard aggregates watch the transaction list +
  `.when` reload skeletons; "Other" = direction-blind ladder, unwired memory,
  P2P fallback, allowlist dropping credit senders; LLM field locator is
  awaited on the capture path; LLM/embedder channels likely absent in the
  WorkManager isolate (T-207d spike); streak chip is the only shell Settings
  entry and its count is untruthful; Settings shows "Version 2.4.0".
- Decisions taken here: T-205 builds on the shipped ADR 0031 correction path
  (does not wait for T-177c/d); schema versions are assigned at task start
  (queue in roadmap); design-system sections stay named; parallel workers
  allowed on disjoint files per roadmap hot-file locks.
- Board: TASKS.md slimmed to one line per task (evidence moved to briefs);
  Ready = wave 1–2 parents with "Now:" children; roadmap has waves, hot-file
  locks and the schema queue (`sms_facts` → minor-unit money → dashboard).
- Owner answers (2026-10-10): refund attribution = purchase period (T-209
  closed); ADRs 0033–0036 accepted; card defaults 1–6/8 accepted; refund
  exact-reference matches suggest-only (T-100b1c dropped). Non-blocking
  defaults: APKs move to GitHub Releases before deleting `apk-downloads`;
  prefer Tesseract over ML Kit for T-177g spikes; admit `KOTAKD` natively with
  fixtures (T-170d3), `HDFCBN`/`ICICIP` only with fixtures.
- New finding: `SmsFilter.kt` bank tokens lack `KOTAKD`/`HDFCBN`/`ICICIP`, so
  those senders are dropped natively — promoted to P0 T-170d2/d3.
- T-206: PR #153 merges the integration branch; 18 stale bot branches are
  listed for owner deletion in [T-206](docs/tasks/T-206.md).

## 2026-10-11 — Owner 12-item batch merged on integration branch (T-202)

- Branch `claude/paisatrack-multi-feature-mh2nhw` (pushed). Schema v20 / ADR
  0032 (recurring_override, sms_transaction_links). Merged: Trends insight
  history (12-month retention, filters, restore); recurring override backend,
  Recurring section, Activity badge; supporting SMS classifier/linker
  (dividend, RD, EMI notice, UPI collect) with retention, backup, nightly and
  history-import linking; detail page (source SMS above details, curated
  copy, technical card, recurring control; category restored under amount);
  Sort list redesign and matched back/skip; On-device AI model + embedder
  download; Appearance cards; dismissible toasts (undo 6s, SnackBar close
  icon); Android 16 edge-to-edge (overlay style, cutout, sheets use safe
  area); dashboard BudgetStatus (Safe today never negative, same days-left,
  Net flow In/Out, card wraps); data-test fixture repairs.
- Owner answers: refund window 3–5 business days, match up to 31 days
  (attribution default still open, T-209). Owner allows UI rewrites.
- Known: owner data shows ~96% spend in "Other" — P2P now falls back to
  `other` per ADR 0011 (stale test updated); T-205 owns the fix. Full suite
  is slow (~15 min, per-file compile; T-210).
- Open/running at handoff: T-203 flicker/speed (`wt-flicker`), bot-branch
  triage (`wt-triage`), T-204 icon/UX pass, T-206 merge to main + owner
  deletes remote branches (session proxy cannot delete). No device QA.

## 2026-10-04 — T-100a-S1 read-only refund preview host complete

- Luna High added a persisted-row preview API; Sol independently reviewed it.
  Exact complete references, shared source-currency/eligibility rules, full
  touched-link validation, ambiguity/cap checks and checked decimal arithmetic
  preserve source facts. No UI/capture caller, link write or calendar total
  change. Original/refund dates and gross/linked/remaining pair amounts remain
  review evidence only. ADR 0026 records the bounded engineering contract.
- Focused/default and America/New_York tests 23/23 each; full serial Flutter
  suite 1,327/1,327 with zero failures/skips. Encrypted migration executed.
  Analyzer, three-file formatter, documentation links and diff checks pass.
  Review fixed cross-candidate link contamination, incomplete already-linked
  closure, zero-credit acceptance and fractional/large-amount cap hazards.
- Refreshed GitNexus: 8,954 nodes, 20,972 edges, 408 flows. Final complete scan:
  9 files/58 symbols, LOW risk, zero reported flows; all 58 symbols returned,
  including added files. Global flow inventory remains capped (1,074
  unranked entrypoints, 1,441 skipped callees, 34 cut walks), so source review
  and actual tests corroborate callers. Only tests call the new preview API.
- Merchant suggestions remain default-off. Owner holdout/cohort/threshold,
  physical live/resume capture and T-177f staged rollout gates remain open;
  a synthetic cohort/Wilson extension cannot close them. Card audit preparation
  found paymentSourcesProvider reconciles on load; its future read-only report
  must use a separate Settings route and direct repository.
- Owner refund-period question remains unanswered; T-100 persistence, durable
  Undo and canonical net totals plus card accounting/ownership/schema contracts
  remain open. Phone is connected at the existing endpoint; only connection
  metadata was checked. No owner GUI/SMS/DB/log/backup/key access, phone update
  or APK publication. Both protected stashes and the T-194 trial remain intact.
