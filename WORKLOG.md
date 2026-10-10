# Current Handoff

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

## 2026-10-04 — T-190a1 read-only card source audit host complete

- Luna High implemented the isolated Settings route; Sol independently
  reviewed it, with a second Luna reviewing/debugging host acceptance. The
  repository uses one consistent read transaction, SQL groups and bounded
  timestamp/ID pages. It exposes retained source/currency/lifecycle/flag facts,
  safe identifier suffixes, absent labels and observed identity conflicts.
  Product/ownership stay unverified; historical merged collisions stay unknown.
- The real route bypasses paymentSourcesProvider's transfer reconciliation.
  A control fixture proves the seeded reciprocal pair would reconcile; all
  source/transaction/link/feedback values and real Dashboard aggregates remain
  unchanged across report reads and Settings navigation. No writes, schema,
  backup, capture or financial projection changes. ADR 0027 accepts host audit
  only; ownership preview/confirmation/Undo and card accounting remain open.
- Focused Settings/audit tests 15/15 in default and America/New_York; analyzer
  clean; formatter six changed Dart files unchanged. Final serial full suite
  passes 1,338/1,338, no failures/skips; encrypted migration executed.
  Markdown links (154 files), board/handoff invariants and diff checks pass.
  Refreshed GitNexus: 9,131 nodes, 21,375 edges, 416 flows. Complete scan:
  16 files/184 symbols, all 184 returned, 11 reviewed audit-read/display/paging
  flows, HIGH risk; no true partial/truncated flags. Global inventory still
  omits 1,092 entrypoints, 1,459 callees and 35 walks. The provider's empty
  graph references and existing Bloom test's one-line main span do not prove
  absence of calls or change; actual provider/route tests and diff review cover
  those boundaries. Widget teardown now flushes Riverpod disposal timers
  and closes the synthetic DB in real async; no diagnostic logging remains.
- Full-suite regression reached an existing reset-dialog overflow at
  320×568/2× after fixing the test's offscreen edge tap. Its content is now
  scrollable; unchanged destructive confirmation logic, full 48dp surface,
  no-overflow and Cancel dismissal are covered without reducing text scale.
- Merchant suggestions remain default-off; consented holdout/cohort/threshold,
  live/resume device evidence and T-177f rollout gates remain open. The owner
  refund-period question remains unanswered; T-100 linking/Undo/net totals and
  card ownership/instrument/schema/accounting contracts remain open. No owner
  GUI/SMS/DB/log/backup/key access, phone update or APK publication. Both
  protected stashes, isolated T-194 trial and .handoff/paused remain intact.
