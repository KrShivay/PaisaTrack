# Current Handoff

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
