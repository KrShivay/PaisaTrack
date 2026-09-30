# Current Handoff

## 2026-09-30 — T-164e Activity/Dashboard timestamp display

- Added `formatTxnClockTime` so Activity/Dashboard rows localize an instant
  once for the 12-hour clock; epochs, stored values, parsing, export, calendar,
  filters, SMS, and capture are unchanged. Activity now groups by full local
  calendar date, separates same month/day across years, and uses DST-safe
  Today/Yesterday labels while preserving row order and stored instants. The
  row-clock slice and independently reviewed grouping slice are complete; the
  broader detail/export/search/filter/import/SMS contract remains open in Ready.
- Deterministic row tests cover `2026-07-10T18:30:00Z` at +05:30 (`12:00 am`),
  a changed -04:00 offset (`2:30 pm`), unchanged epoch, detail/grouping parity,
  production row widgets, and a fixed September 2026 Dashboard anchor. Grouping
  tests cover same-day cross-year totals/order, UTC-backed local midnight, and
  spring/fall DST. Row-clock pre-edit GitNexus impacts were LOW/exact; grouping
  pre-edit impacts were LOW. Code commits `3bd1b4e821d813ae744c93ca18927ad231bc4253`
  and `6b9bc84033fc193ee6497638caf15b1e0786c973` are pushed to their respective
  `codex/t164e-*` branches.
- Verification: row-clock focused 32/32, timezone widget checks 21/21, then-full
  suite 947/947; grouping focused 28/28 in `TZ=Asia/Kolkata` and
  `TZ=America/New_York`, full suite 951/951, analyzer/format/diff clean, and
  GitNexus row-clock final 8 files/10 symbols/0 processes/LOW and grouping
  all-scope 5 files/7 symbols/0 processes/LOW. T-176 physical
  QA on published v0.1.3+2011 source `3b2fb6b` confirmed the Ask composer is
  occluded by the IME in default portrait at 1× and 1.5×, with repeated settled
  IME metrics and local screenshots. Settings were restored; no messages/data
  changed, and physical acceptance did not pass.

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
