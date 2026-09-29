# Current Handoff

## 2026-09-29 — T-192 release candidate preparation

- Started on a fresh branch from reviewed main `d8a09a8`. Target package version
  is `0.1.3+2007`; the existing release key is present in the primary checkout
  and will be accessed without printing its contents. The only connected
  physical device is the user's phone, so all run/install/log commands will be
  explicitly emulator-scoped. No APK publication or phone mutation is planned
  during candidate preparation; backup export is still pending.
- Candidate: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`,
  56,685,036 bytes, SHA-256
  `1b3ba4a18f43e9c66fe65c752f2d69393df4a90e05701094bc0c7e439129215b`.
  Package `com.paisatrack`, name `0.1.3`, effective ARM64 code `4007` (Flutter
  split-per-ABI offset +2000 from source code 2007). Certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163` matches
  the installed production signer. Candidate is 131,344 bytes larger than the
  published APK.
- Verification: signed release cold-started on fresh synthetic AVD
  `emulator-5556`; Home, Activity, Trends, and Ask routes opened; force-stop /
  relaunch returned to resumed `MainActivity` with no filtered AndroidRuntime,
  Flutter, or WorkManager errors. Flutter suite 894/894, `flutter analyze
  --no-pub`, Android `:app:testDebugUnitTest`, and `git diff --check` passed.
  Existing AVD had a differently signed app and was left intact; a fresh AVD
  was used. Manual Entry opened, but saving a synthetic transaction and backup
  export/import were not verified. Candidate is not published and was not
  installed on the phone; physical backup/acceptance remains pending.

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
- Remaining T-177a audit: transaction-detail Confirm currently creates no
  feedback and therefore cannot train this threshold; live/historical/resumed
  provider traces, T-140/T-143 reconciliation, and cohort precision/coverage
  baselines are still open. This milestone does not complete T-177a. No schema,
  phone, or APK changes were made.
- Full Flutter suite 898/898; `flutter analyze --no-pub`, changed-file
  formatting, and `git diff --check` clean. Fresh pre-edit GitNexus impact was
  HIGH (47 symbols / 4 flows); detect-changes reports 9 symbols, 5 files,
  0 mapped processes, LOW. Independent review pending.
