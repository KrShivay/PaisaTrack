# Current Handoff

## 2026-09-30 — T-164e Activity/Dashboard row clocks

- Added `formatTxnClockTime` in `lib/core/format.dart`; Activity and Dashboard
  transaction rows now convert an instant to local time once before rendering
  the 12-hour clock. The timestamp epoch, stored representation, parsing,
  grouping, export, calendar, filter, SMS, and capture behavior are unchanged.
- Deterministic tests cover `2026-07-10T18:30:00Z` at +05:30 (`12:00 am`), a
  changed -04:00 offset (`2:30 pm`), unchanged epoch, detail/grouping parity,
  and both production row widgets. Dashboard test data uses a fixed September
  2026 period anchor. No emulator, phone, or private user data was used.
- Pre-edit GitNexus impact was LOW/exact: Activity row formatter 2 symbols / 1
  direct caller / 1 process; Dashboard row formatter 1 / 1 / 0; core `_clock12h`
  2 / 1 / 0. Independent review approved the bounded slice and fixed period
  fixture. The broader T-164e display/date/filter/import contract remains open.
- Focused suite: 32/32; Activity/Dashboard widget suites with
  `TZ=Asia/Kolkata`: 21/21; full Flutter suite: 947/947;
  `flutter analyze --no-pub`, Dart formatting, and `git diff --check` clean.
  GitNexus final graph detection: 8 files, 10 symbols, 0 processes, LOW risk.
  Branch commit/push are pending.

## 2026-09-30 — T-194 APK-size trial tracking

- Signed ARM64 v2011 candidate: `codex/apk-size-trial` commit `4a9fdfa`,
  26,180,416 bytes, SHA-256
  `cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`.
  Same-source control confirms all six native libraries are unchanged by the
  release-only packaging setting; package/version/signer, ZIP, and alignment
  checks passed. No install or publication occurred.
- T-194 is Ready for physical acceptance. When the supported ARM64 phone is
  online, measure installed storage and cold-start behavior before adoption.
  This tracking change is docs-only; the Gradle experiment remains isolated on
  the candidate branch. GitNexus docs-only detection found 9 touched section
  symbols, 0 processes, LOW risk.

## 2026-09-30 — ARM64 0.1.3+2011 release

- Built the signed ARM64 APK from main `3b2fb6b` after changing only the
  release version to `0.1.3+2011`. Published it to `apk-downloads` in commit
  `6ac898f564bfd307455a1b7201ab229a3fe09c80`. The 56,750,764-byte APK has
  SHA-256 `218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`,
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4011`,
  and production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
- Physical v2011 launch is unverified because the device is offline; the phone
  remains on `0.1.3+2010` (effective code `4010`; `firstInstallTime` remained
  `2026-09-26 22:20:54`). No v2011 phone install was attempted.
