# Current Handoff

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

## 2026-10-04 — T-201 integrity repair active; physical identity defect proven

- **Paused at the user's explicit request.** No commit/push. Production/test
  changes remain in the shared working tree; worker interrupted. Capture's 153
  focused tests and consumer repository/UI/category/recurring/transfer focused
  checks pass; latest consumer analyzer/diff are clean. A final nullable-category
  widget regression was being added when paused; its final result is unverified.
  Resume by inspecting that worker diff/checkpoint, then final full Flutter suite
  with encrypted migration executed, relevant timezone checks, formatter/docs,
  fresh complete graph review and the disconnected-phone QA proof. Do not treat
  focused results as final acceptance. SDK ownership must be explicitly acquired
  before resuming checks. No owner app update or APK publication.

- User supplied transaction-integrity bug report; three Luna High read-only
  audits and Sol source review confirmed capture, duplicate/retry, totals,
  category Undo and inference issues. Task/report and ADRs 0028–0031 record
  bounded contracts. Production/test implementation remains sequential.
- First physical milestone passed in isolated RecoveryQA on Motorola Edge 50
  Pro, Android 16/API 36: actual synthetic 3GPP PDU through SmsReceiver and
  injected MatrixCursor through SmsInboxReader accepted the same HDFCBK alert,
  but IDs differed when received DATE was 60 seconds after sent DATE_SENT.
  Marker SMS_IDENTITY_QA_OBSERVED: accepted both=true, idsMatch=false,
  dateSentRequested=false, timestampDifferenceMillis=60000. No owner provider,
  app, data or logs accessed; only RecoveryQA updated. Carrier/default-provider
  delivery remains outside this synthetic proof.
- User briefly requested a pause, then resumed. The preserved native query
  seam, fixed-data QA probe and integration test are uncommitted; no identity
  fix landed before the pause. Replacement Luna High implements sent-time IDs
  and exact legacy aliases under ADR 0030 with exclusive Flutter/Gradle use;
  two Luna agents prepare/review read-only. Sol independently reviews and owns
  docs/integration. Identity host review now passes: 79 focused tests, clean
  analyzer/diff, Android unit tests and independent Luna/Sol reviews. Shared
  validation preserves exact stored claims; per-page plus bounded 4,096-claim
  last-DATE cohort checks reject conflicting input without rewriting earlier
  pages. Alternate mappings are transient, so cross-run ambiguity remains a
  documented boundary. Capture repairs now pass 153 focused tests, analyzer,
  formatting, diff checks and Android unit tests: real bank alerts and negative
  controls, lifecycle-aware duplicates, bounded once-per-run retries, safe
  forced-scan checkpoints, conservative numeric VPA fallback, valid template
  dates and explicit user-rule descriptions. Consumer totals/Ask, expected-event,
  shared recurring projection and normalized owned-transfer guard are implemented
  with focused tests; final mask-style guard rerun is included in pending combined
  verification. Independent source review passes. Recurring reconciliation
  re-reads latest status memory after awaited detection, preserving concurrent
  user intent. Category receipt/preflight and both detail UI paths are active;
  combined consumer/analyzer and final acceptance remain pending.
- Post-fix physical integration installed/launched only RecoveryQA and started
  its Dart VM, but forwarding closed before test load/probe marker. Device
  acceptance remains open; no passing post-fix result is claimed. SDK was
  explicitly released before the next implementation handoff. A permission-free
  native intent fallback is implemented only in RecoveryQA under ADR 0028;
  normal/QA Android unit runs pass (33 tests) and QA APK compilation passes.
  Manifest verifies isolated app ID/debuggable and absent SMS permissions.
  Phone is disconnected; user asked to reconnect while consumer work proceeds.
  No post-fix physical marker is claimed, and the failed Flutter run stays open.
  No commit yet.
- GitNexus baseline refreshed (9,131 nodes/21,375 edges/416 flows); global flow
  inventory capped and MCP cached index stale, so fresh CLI plus source review
  used. HIGH capture and CRITICAL model/categorizer/date risks warned before
  edits. RawSms impact: 92 symbols/15 flows. No final full-suite acceptance yet
  for this unfinished slice; previous 1,338 pass belongs to dcfdab4 only.
- Preserve protected stashes, isolated T-194 trial and .handoff/paused. No APK
  publication or owner update. Suggestions default-off; refund-period and
  ownership/card accounting decisions remain open. Historical persisted
  suppression/lifecycle errors require grounded repair; no blanket backfill.
