# Current Handoff

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
  suite: 954/954; analyzer clean. The installed phone still runs the original
  build; T-176 and T-167c physical acceptance remains open pending review and
  re-test.

## 2026-09-30 — T-194 APK-size trial tracking

- Signed ARM64 v2011 candidate: `codex/apk-size-trial` commit `4a9fdfa`,
  26,180,416 bytes, SHA-256
  `cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`.
  Same-source control confirms all six native libraries are unchanged by the
  release-only packaging setting; package/version/signer, ZIP, and alignment
  checks passed. The candidate remains unpublished and was not installed.
- T-194 is Ready for physical acceptance. The supported ARM64 phone was online
  for the separate 2026-09-30 published-release launch, but candidate installed
  storage and cold-start were not measured. The Gradle experiment remains
  isolated on the candidate branch. GitNexus docs-only detection found 9
  touched section symbols, 0 processes, LOW risk.

## 2026-09-30 — ARM64 0.1.3+2011 release

- Built the signed ARM64 APK from main `3b2fb6b` after changing only the
  release version to `0.1.3+2011`. Published it to `apk-downloads` in commit
  `6ac898f564bfd307455a1b7201ab229a3fe09c80`. The 56,750,764-byte APK has
  SHA-256 `218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`,
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4011`,
  and production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
- On 2026-09-30, fetched `app-release-arm64.apk` from that exact public commit,
  reverified its size, SHA-256, package/version/code, ARM64-only native ABI, and
  production signer, then installed it on the motorola edge 50 pro with
  `adb install -r` (success). The installed base APK matched the published
  artifact byte-for-byte at 56,750,764 bytes and the same SHA-256. The phone
  reported code `4011` before and after; `firstInstallTime` stayed
  `2026-09-26 22:20:54`, confirming in-place replacement only, not data
  integrity. Before this install, the phone held a same-version 130,104,007-byte
  local build with a different hash.
- `MainActivity` launched and remained resumed with a live app process. A
  recent, narrowly filtered AndroidRuntime/linker log sample contained no app
  fatal or native-load failure markers. The APK includes the Flutter, SQLCipher,
  LiteRT-LM, and MediaPipe ARM64 libraries; optional native inference paths were
  not exercised. No private screens or financial data were inspected. T-193
  preview/apply/undo, T-194 storage/cold-start measurement, and the separate
  responsive, capture, and recovery device gates remain open.
