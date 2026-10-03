# Current Handoff

## 2026-10-03 — @claude review: T-195 PASS

- T-195 (`126f7d4`) review PASS: ADR 0021 matches code; one `RawSmsRetention`
  predicate drives nightly purge, backup export/restore and the unreadable
  count; the relinker links only exact evidence matches, atomically, and never
  edits transactions; no schema change; regression tests read and
  non-vacuous (match/skip/ambiguous/paused/conflict/idempotent, nightly,
  backup). Tests were not re-run in this session (shell approval
  unavailable); relied on the recorded 1185/1185 evidence.
- Removed T-195 from the board. Its only open item, the owner-phone re-link
  check, moved into T-170b. Nothing else In Review; T-196–T-198 are Ready
  for @codex.

## 2026-10-03 — Cloud session: T-195, T-196, T-197

- T-195 (ADR 0021): SMS behind a transaction or "Not a transaction" are kept;
  unlinked SMS expire after 7 days (flag `raw_sms_retention_days` retired);
  backups carry linked SMS; Settings → "Restore SMS sources" re-links exact
  inbox matches (`txn_<id>` + evidence spans), skips and counts the rest.
  Shared `readInboxPages` now drives history import, catch-up and re-link.
  Backup +~340 B per kept SMS (16 MiB cap ≈ 12k SMS-backed transactions).
- Evidence: suite 1185/1185, NY-TZ touched dirs 642/642, analyze 0.
  Owner phone still needs the re-link check.
- T-196: "TRANSACTION DETAILS" card on the detail screen (stored fields only,
  48dp copy buttons); suite 1192/1192. In Review; owner-phone check open.
- T-197: Activity lost its scroll because the category picker's autofocused
  keyboard flipped the portrait layout to the short-height one; the
  breakpoint now ignores the keyboard. Suite 1196/1196.
- Push from the cloud failed (403, Claude GitHub App has no repo access);
  commits are local until access is fixed. The T-177 R3 entry is in Git
  history (`c381756`).

## 2026-10-03 — Owner-phone defects fixed; release 0.1.6+2015

- Owner-phone QA (data exported by owner): UNDO-1 passed (category change,
  toast over detail, Undo restored it). Found and fixed: ISO/INR claim copy
  and a false "committed to rent" caption (`5dd0248`); Ask could not find
  VPA-only payees such as `payzomato@hdfcbank` — R4 brand-word matching with
  disclosed payees, plus a reviewer-found "ola"/multi-word regression fix
  (`8e4eb65`); emulator-matrix fixes (48dp Ask rows, compact landscape ring,
  provenance badge; `82ba900`); landscape nav/Ask orb under the right system
  bar and Activity header eating the viewport at 2.0x (`9dac2c5`, DRY
  refactor before merge; test fix `89a20c3` after main went red); Trends
  claim titles and day-7 minimum for category deltas (`a09bd1c`); readable
  Ask answers with a "How this was counted" disclosure (`dfb05e6`).
- Release 0.1.6+2015 (`13dd4d5`): suite 1174/1174, Gradle 31/31 + 10/10,
  installed in place (firstInstallTime unchanged, hash matched), cold launch
  1040 ms, published `apk-downloads` `5747e3c`. Open: landscape/2.0x/3-button
  recheck on this build (phone back in portrait); the stale pre-day-7
  category card cleared once insights regenerated. VPA-only rows still display raw
  VPAs, Top merchants shows several "Unknown" rows. R2 entry is in Git
  history (`f730857`). T-195–T-198 are now Ready on the task board.
  Follow-up release 0.1.7+2016 (`016465d`, adds the month-over-month badge
  fix `37beb17`): suite 1176/1176, installed in place, published
  `apk-downloads` `0e151f2`.

The roadmap-planning entry (plans, ADR 0020, T-190 briefs) is in Git history
(`c381756` and earlier).
