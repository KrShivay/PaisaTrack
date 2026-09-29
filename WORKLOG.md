# Current Handoff

## 2026-09-30 — T-193 legacy currency repair

- The source-backed per-transaction detail preview/apply/undo repair was
  independently reviewed with no blocker. It requires retained/unexpired
  linked SMS, exact amount evidence matching the body and stored paise, and one
  adjacent `Rs`/`Rs.`/`INR`/`₹` token; it changes only currency fields and
  preserves later edits on undo. USD, bare `$`, manual/imported/unknown,
  duplicate/deleted, stale, mismatched, or expired cases remain unchanged.
- Added a synthetic encrypted chunked-backup restore integration test. A legacy
  null-currency transaction with retained raw SMS and amount evidence remains
  previewable after restore and successfully applies/undoes INR. Its expired
  counterpart is detached from its omitted SMS and remains ineligible. No
  production code, schema, migration, private data, or APK changed.
- Focused backup and repair-service tests 40/40; full Flutter suite 915/915;
  `flutter analyze --no-pub`, changed-file formatting, and diff check clean.
  GitNexus detect-changes: 9 documentation section symbols in TASKS, WORKLOG,
  and T-193 notes, LOW risk, no affected processes (the test file has no
  indexed symbols).
  Pre-edit test-scope impact: `SourceCurrencyRepairService` HIGH (31 symbols)
  and `EncryptedBackupService` HIGH (27); neither production class was edited.
  The encrypted restore compatibility-test commit independently reviewed
  without a blocker. Physical UI preview/apply/undo confirmation remains
  pending.
- Published signed ARM64 `0.1.3+2008` to `apk-downloads`, commit
  `7971aeb7df39d210ae68a289fdff5debb20578ca`. APK size 56,750,764 bytes,
  SHA-256 `0f78b18200a899a2cddc9b4d7a02ecce6e18fe8a226e49103b168f910def3930`;
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4008`,
  production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
  Owner reports the in-place phone upgrade preserved firstInstallTime and left
  the app process alive without a crash exit. Synthetic encrypted
  backup/restore compatibility is now covered; physical repair-preview/apply/
  undo acceptance remains open.

## 2026-09-30 — T-192 publish Android 0.1.3+2007

- Published the signed ARM64 APK from current main `1f4f451` to public branch
  `apk-downloads`, commit `02acbef12a5df8159d14bd370a0e47b8a67654de`. The
  README direct download URL is unchanged. Artifact:
  `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, 56,750,680 bytes,
  SHA-256 `0affd549d926814082d6ff1548aefebcda768dcd0d2c1f326e5c11856daa86c3`.
  Package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4007`;
  production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
- The owner verified a fresh encrypted backup off-device before installing.
  Physical in-place upgrade preserved firstInstallTime; the app remained
  foregrounded without a crash exit. Synthetic API35 ARM64 emulator cold-start
  and Home/Activity/Trends/Ask routes had passed for the release candidate;
  Flutter tests 894/894, analyzer, Android unit tests, and diff check passed.
  Manual Entry save and backup restore were not verified. Broader T-167c
  responsive-layout, T-176 screen-inset, and T-179a recovery acceptance remain
  open.
- GitNexus detect-changes returned partial/unknown for the binary-only APK diff
  on unstaged and staged reruns. Manual staged diff contains only the APK.

## 2026-09-30 — T-177a threshold evidence revision follow-up

- Threshold recomputation no longer treats silent `auto` rows as correct.
  Eligible outcomes require category-prediction provenance and either category
  correction feedback or explicit user-confirmation feedback from Activity or
  Weekly Review. Status-only rows and manual entries are excluded. v1/v2
  count-only state is ignored; v3 uses streaming evidence fingerprints and
  deterministic replay of completed chronological cohorts.
- Same-count correction after processing, multi-cohort replay, and both undo
  below 50 outcomes and full category removal reset the learned threshold and
  metadata to the static default. Streaming SHA-256 fingerprints keep stored
  metadata bounded. Focused `decision_policy_test.dart`: 17/17.
- Added an explicit low-trust parse-confirm action to transaction detail. It
  requires retained SMS and field evidence, leaves status/category unchanged,
  deduplicates its versioned feedback, and can be undone. The public-template
  ledger ignores unvalidated legacy positives and invalid/deleted/duplicate
  sources; its v2 cache rebuilds restored v1 counters from evidence. Confirmed
  evidence remains usable after raw SMS retention expires.
- Focused repository, ledger, and detail tests: 38/38. The synthetic
  capture-provenance/replay milestone independently reviewed without a blocker:
  it exercises the live bootstrap, history importer, and resume catch-up runner
  with synthetic messages and local dependencies, and reconciles T-140/T-143.
  The resume fixture does not exercise the lifecycle callback or known-SMS
  boundary. T-177a remains open for a real labeled holdout, physical live/resume
  capture, and a reviewed decision-version contract. No schema, phone, or APK
  changes were made.
- Full Flutter suite 903/903; `flutter analyze --no-pub`, changed-file
  formatting, and `git diff --check` clean. Fresh pre-edit GitNexus impact was
  HIGH for `AdaptiveThresholdPolicy` (47 symbols / 4 flows), CRITICAL for
  `TransactionRepository` (80 / 43 direct) and `TransactionDetail` (77 / 40
  direct), HIGH for `TransactionDetailScreen` (42 / 18 direct) and
  `TemplateTrustLedger` (90 / 12 direct). Exact ledger `refresh` was UNKNOWN
  with two unresolved callers; text search confirmed call sites. GitNexus
  detect-changes reports 25 symbols, 9 files, 4 processes, MEDIUM. Independent
  review pending.
