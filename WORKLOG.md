# Current Handoff

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

## 2026-09-29 — T-167c responsive large-text layouts

- Fixed the confirmed narrow 2× overflow in the floating navigation pill,
  Activity header/list controls, and Trends header/chart. Dashboard controls,
  Manual Entry category selection, and transaction detail layouts adapt to
  narrow and large-text viewports while preserving full labels and 48dp targets.
- Added responsive geometry, semantics, and interaction checks for 320×568 and
  600×900 at 1.5×/2× across the navigation pill, Dashboard, Activity, Trends,
  Manual Entry, and transaction detail. The full HomeShell fixture hangs during
  Drift stream teardown, so the nav presentation is tested directly; physical
  device acceptance remains open.
- Reviewer follow-up keeps nav labels hidden when large text would wrap in the
  fixed-size tab cells, preserves Dashboard streak/period text, labels the Ask
  orb, and lets long foreign-currency Activity amounts wrap to a second line.
- Validation: responsive route suite 42/42; focused changed-screen/inset suite
  56/56; reviewer follow-up focused suite 24/24; full Flutter suite 894/894;
  analyzer, changed-file format check, and diff check clean. Follow-up GitNexus
  impact: Dashboard/nav/Activity row MEDIUM, Ask LOW; shared `BloomAmount`
  impact HIGH was avoided. Detect-changes: 8 files, 9 symbols, 0 processes,
  LOW. Independent review pending.

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
