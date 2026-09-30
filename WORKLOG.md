# Current Handoff

## 2026-09-30 — T-194 ARM64 APK-size trial

- From main `82907bf`, set Android JNI packaging to `useLegacyPackaging=true`
  for the release variant only via AGP's Variant API. The signed ARM64
  `0.1.3+2011` candidate is
  26,180,416 bytes (SHA-256
  `cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`),
  30,570,348 bytes / 53.9% below the 56,750,764-byte published artifact.
  Package, version/effective code, and production signer match. ZIP integrity,
  signature verification, and zipalign pass; the candidate compresses all six
  ARM64 `.so` files and its merged manifest has `extractNativeLibs=true`.
- The debug ARM64 build passes with `extractNativeLibs=false` and six
  uncompressed `.so` entries, so debug packaging retains its default.
- A signed same-source/same-toolchain control with the setting omitted proves
  all six library contents match the candidate. `libapp.so` and `libdartjni.so`
  differ from the older published artifact in both control and trial, so that
  variance predates the packaging setting. No Dart source changed; analyzer
  passed and exact-base full Flutter suite is 942/942. No phone install or APK
  publication. Device storage/cold-start measurement remains pending because
  the supported phone is offline; keep T-194 open.
- GitNexus impact for `useLegacyPackaging` and the Gradle file returned
  UNKNOWN (not represented in the symbol graph); text search found no existing
  setting or consumers. Final `detect_changes(scope: all)` reports 9 touched
  documentation section symbols, 0 affected processes, LOW risk, with no
  partial/truncated result; the Gradle setting and new task brief are not
  represented in the index. Independent review approved the release-only
  experiment after the per-library comparison table was added. Phone storage
  and cold-start acceptance remain open.

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

## 2026-09-30 — T-177a capture-decision version contract

- Read-only audit confirmed the prior synthetic replay already covered live,
  history, and resume providers. The report keeps the intentional wiring gaps:
  live may use the optional field locator and merchant resolver; history/resume
  omit those helpers, use fixed review status, and do not activate merchant
  memory, LLM categorization, or shadow execution.
- Added the shared `capture_decision` writer/reader contract to the existing
  `confidence_json` block. Parsed rows record `capture-decision-v1` and explicit
  `policy` (live) or `fixed_review` (history/resume) status mode. Legacy,
  malformed, and unsupported metadata reads as unknown; no row is backfilled.
  ADR 0018 documents versioning, backup/deletion compatibility, and that the
  marker is not a correctness label. No schema, generated code, inference, or
  category behavior changed.
- Updated the replay fixture to read persisted decision versions and assert the
  status mode from all three synthetic production provider paths. No real SMS,
  phone, emulator, network, or private user data was used; no accuracy or
  holdout claim is made. T-167c moved to Ready with physical-device QA pending.
- Pre-edit GitNexus impact was HIGH for `_transactionCompanionFor` (9 symbols,
  4 flows) and CRITICAL for `SmsIngestor` (29 symbols, 16 direct, 6 flows).
  The history/resume provider impact returned UNKNOWN; text search confirmed the
  actual call sites. HIGH/CRITICAL warnings were delivered before edits.
  Independent review found and rechecked the fixed-status mode edge with no
  blocker.
- Focused provenance/ingest/backfill tests passed 57/57; full Flutter suite
  passed 942/942; `flutter analyze --no-pub` and `git diff --check` are clean.
  GitNexus final graph detection: 10 files, 28 symbols, 0 processes,
  LOW. Real chronological holdout and physical capture/resume coverage remain
  open.
