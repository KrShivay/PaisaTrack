# Current Handoff

## 2026-10-04 — T-167b host accepted; first feature in parallel

- Custom Activity, Dashboard, Settings, Review, and notice controls expose
  meaningful semantics and 48dp targets. Compact/large-text search, complete
  amounts, and scrollable Sort content preserve legibility and navigation
  clearance. Independent review passed; T-167b is removed from the active board.
- Full serial suite 1,285/1,285, including encrypted schema migration;
  America/New_York touched directories 384/384; analyzer clean; formatter
  12 edited Dart files unchanged; Markdown links and diff checks pass.
  Complete GitNexus scan before acceptance: 17 files, 39 symbols, zero reported
  processes, LOW risk, no partial/truncated result. Refreshed index: 8,825 nodes,
  20,659 edges, 407 flows. Its capped global process inventory remains an
  inference limitation; source review and actual callback tests cover UI paths.
- Signed arm64 0.1.10+2019 compiled and installed in place, effective code 4019,
  last update 2026-10-04 03:06:24; first install unchanged at
  2026-09-26 22:20:54. Artifact: 57,144,360 bytes, SHA-256
  `4e96bb36bfd02a02228942b642ab1db079325b0a9dfd6f0205e1a15d4f649ea2`.
  Pulled installed base APK matches that exact byte count and SHA-256.
  Signer, ZIP integrity, alignment, and six arm64-only native libraries pass.
  No owner UI, SMS, records, database, or logs were read; physical TalkBack,
  QR Sort, confirmation UI, and native-back gates remain open.
- The requested feature sequence is recorded in the T-177b-S1 brief and
  delivery plan. Production enablement remains gated by T-177a/T-177f; both
  original stashes and the isolated T-194 size trial remain preserved.

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
