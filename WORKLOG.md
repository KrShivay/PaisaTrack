# Current Handoff

## 2026-10-03 — T-177a source/document reconciliation complete

- The 2026-09-30 report accurately described its source revision; commit
  `f730857` added deterministic merchant resolution to history and resume on
  2026-10-02. Current report/ADR/task wording now distinguishes that history
  and records the v2 writer while excluding earlier v1 markers from v2 evidence.
- Current capture wiring uses merchant resolution in all three paths;
  history/resume skip new embedding searches but an existing learned/similarity
  alias can still request review. Production category capture
  does not wire merchant-memory or category-LLM callbacks. Live parser LLM uses
  the runtime's constant default; persisted `enable_local_llm` is not wired to
  `llmRuntimeProvider`. T-143c1–c3 tooling is complete, but production capture
  does not schedule `ShadowPipelineRunner`.
- R-12 documentation discrepancy is reconciled and independently reviewed.
  R-21 stale-edge behavior is host-fixed and regression-tested by T-165b;
  R-04 device latency remains
  unmeasured and routes to T-165a's 10k/50k release-hardware profile.
- Focused capture/provenance tests pass 67/67; 140 Markdown files pass link
  checks; `git diff --check` is clean. This prose-only slice did not rerun or
  claim the full Flutter suite. Owner selection of a consented chronological
  period and approval/revision of proposed thresholds, real holdout, and
  physical live/resume evidence remain open.
- Final GitNexus `detect-changes --scope all --limit 1000 --repo .`: 8 files,
  29 symbols, 0 flows, LOW risk; no partial/truncated result notice. Parent
  independent review passed. T-177a itself remains In Review for owner gates.

## 2026-10-03 — T-167j host implementation in review (device gate open)

- Home back now honors the active tab's `maybePop` and vetoes, retains all four
  tab Navigators, returns non-Home roots to Home, and uses an accessible
  two-second Home exit confirmation without popping an enclosing route.
  Predictive Android transitions are scoped to the active uncovered tab;
  inactive/covered tab tickers are disabled, and programmatic tab state follows
  taps and PageView swipes. ADR 0022 records the behavior.
- Regression evidence: initial focused cases 0/4; programmatic Activity request
  → back Home → repeated Activity request also failed before provider sync.
  Current focused suite 17/17; `America/New_York` shell/home suites 60/60; full
  Flutter suite 1,246/1,246; analyzer, formatter, documentation links, and diff
  checks pass. The SQLCipher migration test ran in the full suite.
- Physical API 36 IME and native predictive gesture acceptance remains open;
  the phone was disconnected, no device was changed, and no private data was
  inspected. The isolated recovery-QA fixture and launcher are preserved under
  `.dart_tool/qa/`; both are `com.paisatrack.recoveryqa` v0.1.7/code 2016,
  built for arm64 with no SMS permissions, and signed by the local debug key.
- Follow-ups: owner-run T-167j IME/predictive checks and the existing T-176 /
  T-167c device gates; consented T-177a holdout/period decision; keep T-194 on
  `codex/apk-size-trial`; signed release build and APK publishing remain open.
  Host acceptance moved T-167j to In Review, not Done.

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
