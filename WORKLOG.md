# Current Handoff

## 2026-10-04 — T-177b-S1 host complete; rollout gates open

- Transaction detail now offers a default-off, exact-payee category suggestion
  from at least two eligible, unanimous explicit category outcomes. The
  separate Accept/Undo receipt changes category and feedback only; it preserves
  status, amount, direction, parse evidence, identity, and financial eligibility.
  Identity collisions, stale evidence, ambiguous names, mixed history, rules,
  and ineligible or untrusted outcomes abstain. Independent source review passed.
- The regression-first unsaved-note case failed when refreshing category state
  reseeded the form; the fix now refreshes category caches without resetting
  the note seed, and the same test passes across Accept and Undo.
- Full Flutter suite 1,304/1,304; encrypted-schema migration executed without
  skips; touched set in `America/New_York` 54/54; analyzer clean; formatter 10
  Dart files unchanged; Markdown links and diff checks pass. Final refreshed
  GitNexus all-change and compare scans each cover 16 files and 56 changed
  symbols, with one reported affected flow and medium risk; structured results
  report `partial=false` and `truncated=false`. Indexed symbols include
  `MerchantCategorySuggestionRepository`,
  `merchantCategorySuggestionProvider`, `MerchantCategorySuggestionPanel`, and
  `hasCategoryPredictionEvidence`; repository context links the provider,
  detail accept action, and tests. The refreshed index has 8,896 nodes,
  20,835 edges, and 408 flows. Its global flow inventory is capped (1,067 of
  1,267 candidate entrypoints were not ranked; 1,429 callees and 34 walks were
  omitted), limiting global flow discovery but not the complete changed-symbol
  scan.
- T-177b-S1 is host-complete and removed from the active board. T-177a owner
  holdout/device/threshold decisions and T-177f staged suggestion release remain
  open; production remains default-off. No schema, capture path, phone, APK,
  owner data, or automatic categorization changed.

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
