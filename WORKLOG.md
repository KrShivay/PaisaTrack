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

## 2026-09-29 — T-176 global bottom-inset acceptance

- Added Trends and Settings final-content geometry checks at 24dp gesture and
  48dp three-button insets. Existing inset/detail tests cover category FAB and
  Manual Entry keyboard behavior, plus transaction detail in modal and
  full-screen sheets with keyboard and 1x–2x text. No production gap was
  demonstrated, so the shared inset contract is unchanged.
- The 320×568/2× layout repro also produced horizontal overflows in the
  HomeShell navigation pill (`home_shell.dart:250`), Activity header
  (`transactions_screen.dart:220`), and Trends header
  (`insights_screen.dart:73`); these are tracked by T-167c. Not transactions,
  nested destination/action-sheet routes, Ask keyboard behavior, compact /
  landscape large-text combinations, and physical-device QA remain open. The
  phone was disconnected.
- Validation: focused inset/detail/Ask suites 24/24; full Flutter suite
  866/866; `flutter analyze --no-pub`, formatting, and `git diff --check` clean.
  GitNexus detect-changes: 3 files, 17 symbols, one affected flow, MEDIUM risk
  (the geometry test exercises `ForTabContent`); no production code changed.
  Independent review pending.
