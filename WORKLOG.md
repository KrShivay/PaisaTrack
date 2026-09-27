# Current Handoff

## 2026-09-27 — Independent reviews and release version metadata

- T-157b and PV-02 passed independent review and were removed from In Review.
  T-176 and T-179a remain open for physical-device acceptance.
- Added T-180 for Weekly Review status persistence: Keep must persist
  `confirmed`; Undo must persist `needs_review` and restore the queue row once.
- Set the next Android release metadata to `0.1.1+3`. The download link still
  serves the published `0.1.0+2` APK; its replacement size will be recorded
  after the signed artifact is built and verified.
- Independent review ran 26 focused Flutter tests and `flutter analyze
  --no-pub`; all passed. No APK or device action was performed.

## 2026-09-27 — T-179a safe key-loss recovery

- Added generation-key recovery from the key-loss screen while preserving the
  old encrypted database family and key. Recovery validates/imports before
  activation, keeps retry state on failures, and fails closed on missing or
  ambiguous generation metadata. Settings reset and nightly work share a
  cross-engine database lock; reset holds it through fresh DB seeding.
- Validation: Flutter suite 768/768; `flutter analyze --no-pub` clean; Android
  keystore unit tests + app Kotlin compile passed; API 35 ARM64 emulator
  integration 1/1 passed using the real Keystore slot and SQLCipher, followed
  by successful MainActivity launch. Physical phone and original backup untouched.
- GitNexus refreshed; `detect-changes --scope all` reported 20 files, 319
  symbols, 6 affected flows, HIGH overall impact, no partial/truncated result.

## 2026-09-27 — PV-02 aggregate parity and truthful dashboard scope

- Added a corpus-seeded SQL parity test that seeds all 20 current corpus rows and
  pins eligible spending/credit IDs, excluded IDs, totals, category totals, and
  trend totals. The corpus `long_history` descriptor says 125 rows but contains
  only two; no broader-history or performance claim is made.
- Added visible dashboard period, settled-spending and credit eligibility,
  known-exclusion, and local-record coverage explanations. Loading/error states
  do not present an exclusion amount as if aggregation succeeded.
- Kept the monthly budget action ahead of the detailed disclosure. Placed the
  disclosure after Recent so the lazy final transaction row remains reachable;
  geometry coverage verifies both it and the final disclosure line clear the
  floating navigation pill.
- Verified: focused dashboard/shell/corpus suite **16/16**; analyzer clean; full
  Flutter suite **764/764**, exit code 0; `git diff --check` clean. The initial
  full run caught a dashboard navigation geometry regression; the disclosure
  was moved after Recent and the final test verifies it clears the nav pill.
  GitNexus change map: 8 files / 14 indexed symbols, LOW risk, no affected
  processes. Flow inventory is bounded, so missing flows are not treated as
  proof of no impact.
