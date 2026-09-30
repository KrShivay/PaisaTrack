# Current Handoff

## 2026-10-01 — T-179a isolated recovery QA harness

- Added a debug-only `com.paisatrack.recoveryqa` identity with a QA-only
  manifest, pre-Flutter native guard, and Dart identity RPC. The default debug
  package remains `com.paisatrack`; the QA manifest has no SMS permission or
  receiver. Independent review accepted the identity/manifest boundary.
- Full Flutter suite: 962/962; Android app and Keystore Gradle unit tests:
  41/41; analyzer and formatting clean. The isolated launcher APK is code 4012,
  245,684,950 bytes, SHA-256
  `5e354dc6fefec7f41eb2d7280f37ec426ec6a327ffb2d86c05b2fe8f303022b4`.
  QA `:app:assembleDebug` succeeds; QA aggregate `build`/`assemble` reject
  app release task graphs before packaging.
  `adb devices -l` is empty: no install, synthetic key reset, SAF selection,
  or phone-side recovery was performed. T-179a remains Ready/open for physical
  cold launch, real SAF restore, and fresh-process verification. See
  [T-179a QA report](docs/reports/T-179a-isolated-recovery-qa-2026-10-01.md).

## 2026-10-01 — v2012 owner-phone install and Ask portrait check

- Built and independently reviewed the signed ARM64 `0.1.3+2012` artifact
  from release commit `9f966992f8665c4f7fea72882af1270cb34b3c3b`. Android app
  and keystore Gradle unit tests passed: 31 app tests and 10 keystore tests,
  zero failures. Flutter focused 29/29, full 954/954, analyzer, and formatting
  evidence is from unchanged source at `3d5f310`; the version-only bump did not
  rerun that suite. Artifact metadata and install evidence:
  [v2012 owner-phone report](docs/reports/release-v2012-owner-phone-install-2026-10-01.md).
- The candidate installed via `adb install -r`; package code 4012, installed
  base hash, and production signer matched, while `firstInstallTime` remained
  `2026-09-26 22:20:54`. Ask opened via the production pill. The focused empty
  composer stayed 59–62 px above the real IME at 1×, 1.5×, and 2× portrait;
  at 2× a safe swipe exposed one suggestion control. Close returned Home.
  Font/rotation settings were restored. No messages or transaction edits were
  made; no private records were inspected. Landscape and broader T-176/T-167c
  acceptance remain open. The exact artifact was published to `apk-downloads`
  in commit `79614386e4f5271c5ccefc67eca66368642fb7ae`; only the APK file
  changed.

## 2026-09-30 — T-176 Ask IME route fix

- Physical QA on the published v0.1.3+2011 build from source `3b2fb6b` found
  the Ask composer fully covered by the settled IME at 1× and 1.5×. The phone
  was restored to portrait, font scale 1.0, and Home with IME hidden. No text was
  entered or submitted, no suggestion was selected, and no transaction edits,
  SMS scan, permission, key, backup, reset, or restore operation was performed.
  Geometry and scope: [T-176 physical Ask QA report](docs/reports/T-176-physical-ask-ime-2026-09-30.md).
- The fix adds opt-in keyboard avoidance to the full-screen sheet helper and
  enables it only for HomeShell → Ask; Ask's compact header uses the remaining
  route height after the IME inset. A regression-first test failed before the
  fix (composer bottom 548dp vs 348dp visible); full-window/inset, resized
  window/zero-inset, and nested-modal cases pass. Production HomeShell tests
  exercise 320×568/2× with a 220dp inset and phone-like 434×964/1× with a
  370dp inset, then hide the IME, close Ask, and verify return to Home. Focused
  helper/Ask/HomeShell/category/detail keyboard tests: 29/29; full Flutter
  suite: 954/954; analyzer clean. As of this 2026-09-30 entry, the installed
  phone still ran the original build; the 2026-10-01 update above records the
  reviewed 4012 installation and bounded portrait retest.
