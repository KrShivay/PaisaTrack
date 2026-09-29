# Current Handoff

## 2026-09-30 — T-193 legacy currency repair

- Added an explicit per-transaction detail preview and reversible INR repair.
  It requires retained/unexpired linked SMS, exact amount evidence matching the
  body and stored paise, and one adjacent `Rs`/`Rs.`/`INR`/`₹` token. Template,
  generic, and local-LLM SMS parses are eligible only with verified evidence;
  USD, bare `$`, manual/imported/unknown, duplicate/deleted, stale, mismatched,
  or expired cases remain unchanged. Apply revalidates and writes only currency
  fields; Undo clears them only if unchanged.
- Focused service/detail tests 22/22; full Flutter suite 914/914; analyzer,
  formatting, and diff check clean. Synthetic data only; no migration, parser,
  schema, or production-row changes during implementation. Pre-edit impact:
  TransactionRepository CRITICAL (80), TransactionDetailScreen HIGH (42),
  FieldNormalizer MEDIUM (35), SourceCurrency CRITICAL (274); no shared parser/model/repository was
  changed. Detect-changes: 8 files, 48 symbols, 1 process, MEDIUM. Independent
  review pending. T-177a is parked in Ready, still open, until this
  user-reported issue is reviewed.
- Published signed ARM64 `0.1.3+2008` to `apk-downloads`, commit
  `7971aeb7df39d210ae68a289fdff5debb20578ca`. APK size 56,750,764 bytes,
  SHA-256 `0f78b18200a899a2cddc9b4d7a02ecce6e18fe8a226e49103b168f910def3930`;
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4008`,
  production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
  Owner reports the in-place phone upgrade preserved firstInstallTime and left
  the app process alive without a crash exit. Backup/restore compatibility and
  physical repair-preview/apply/undo acceptance remain open.

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
- Focused repository, ledger, and detail tests: 38/38. Remaining T-177a audit:
  live/historical/resumed provider traces, T-140/T-143 reconciliation, and
  cohort precision/coverage baselines. This milestone does not complete
  T-177a. No schema, phone, or APK changes were made.
- Full Flutter suite 903/903; `flutter analyze --no-pub`, changed-file
  formatting, and `git diff --check` clean. Fresh pre-edit GitNexus impact was
  HIGH for `AdaptiveThresholdPolicy` (47 symbols / 4 flows), CRITICAL for
  `TransactionRepository` (80 / 43 direct) and `TransactionDetail` (77 / 40
  direct), HIGH for `TransactionDetailScreen` (42 / 18 direct) and
  `TemplateTrustLedger` (90 / 12 direct). Exact ledger `refresh` was UNKNOWN
  with two unresolved callers; text search confirmed call sites. GitNexus
  detect-changes reports 25 symbols, 9 files, 4 processes, MEDIUM. Independent
  review pending.
