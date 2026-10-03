# Current Handoff

## 2026-10-03 — T-165b completed

- Owned-transfer reconciliation now uses bounded `idx_transactions_ts` probes,
  reciprocal singleton matching, and transactional stale system-edge cleanup.
  It preserves user-authored links and unchanged generated edge metadata; reruns
  make no writes. T-190b1 is closed through this task.
- Verification: regression fails before the fix; focused 17/17; repository
  tests in `America/New_York` 111/111; full Flutter suite 1,229/1,229; SQLCipher
  migration test 1/1 (not skipped); analyzer clean; formatting, 138 Markdown
  link checks, and `git diff --check` pass. GitNexus: 11 files, 43 symbols,
  one affected test-entry flow (`Main → ToJson`),
  medium risk; the new test entrypoint owns that attribution. No app `main` or
  serialization code changed.
- Evidence and query-plan/performance methodology: [T-165b brief](docs/tasks/T-165b.md).
  Python sqlite3 3.53.3 host
  comparison: 12,800 old candidate rows / 17,044.6 ms vs. 0 accepted pairs /
  25.0 ms after, on the same 10,160-row synthetic fixture; app reconciliation
  test measured 78 ms. These are host/test measurements, not device latency.
- T-177a retains product priority and its owner-run holdout/live-resume gates.
  T-194 stays on its existing branch. Owner-device QA, signed release build,
  and APK publishing remain local follow-ups in their existing tasks; no
  Android SDK or release signing was needed for T-165b.

## 2026-10-03 — Cloud session: T-195 to T-198, T-154b

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
  keyboard flipped the portrait layout to the short-height one; the layout
  choice is now frozen while a keyboard is up (review caught the HomeShell
  padding case). Also fixed a 360dp header overflow. Suite 1208/1208.
- T-198: readable payee titles (display only); Top merchants' "Unknown"
  rows came from `GROUP BY name` binding to `categories.name`; now grouped
  per payee identity. Suite 1205/1205; review findings fixed.
- T-154b: Sort "Not right?" quick corrections; guess recomputed after an
  edit with Keep disabled until it settles; Keep stores it without feedback
  or rules. Suite 1212/1212.
- Reviews: each task had an independent Claude review; T-195 PASS (its
  phone check moved into T-170b); T-196/T-197/T-198/T-154b findings fixed
  before or after commit. T-196, T-197, T-198 and T-154b stay In Review only
  for the owner-phone check.
- Needs the owner's machine: phone QA of T-195 (Settings → "Restore SMS
  sources", a >30-day transaction shows its SMS), T-196–T-198 and T-154b;
  T-176/T-167c landscape + 2.0x + three-button recheck; signed release and
  `apk-downloads` publish; T-194 stays on `codex/apk-size-trial`. No Android
  SDK in the cloud container, so no debug APK build was run.
- Push from the cloud failed (403, Claude GitHub App has no repo access);
  the commits exist only on the cloud branch `claude/great-cannon-16aotf`
  until access is fixed. Next code slice per roadmap: T-165b. The T-177 R3 entry is in Git
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
