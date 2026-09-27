# Current Handoff

## 2026-09-27 — T-181 Ask category query scopes

- Independent review accepted. The local classifier uses category IDs from the
  seeded taxonomy; parent filters expand to descendants, exact children stay
  narrow, and multiple explicit scopes survive validation and SQL filtering.
  Unrelated or duplicate-name ambiguity refuses before merchant lookup.
  Spending queries now require settled eligible transactions in spending
  categories.
- Added seeded taxonomy classifier/query tests, controller end-to-end tests,
  compact multi-category intent coverage, malformed-intent and duplicate-name
  rejection tests, category-scoped breakdown coverage, and ADR 0014. Malformed
  filters (including null arrays and mixed single/list encodings) fail closed.
- Validation: focused assistant suite 42/42; full Flutter suite 799/799;
  `flutter analyze --no-pub`, Dart formatting, and `git diff --check` clean.
  GitNexus `detect-changes --scope all`: 15 files, 42 symbols, 5 affected
  processes, MEDIUM risk, no partial/truncated result. No phone/archive access.

## 2026-09-27 — PaisaTrack 0.1.2+4 Android release

- Built the signed ARM64 production APK from `main` at `b06d315`, with the
  installable build number incremented to `0.1.2+4`.
- APK size: 56,553,692 bytes; SHA-256:
  `9965dcdae9b1011c5325a5f0c5a83f317d69d6fca38cacb5a007ec9e3c211746`.
- Production signing certificate matches the existing published APK. Install
  and launch passed on the connected ARM64 phone. Full T-176/T-179a physical
  acceptance remains open.

## 2026-09-27 — T-180 review persistence and release metadata

- T-157b and PV-02 passed independent review and were removed from In Review.
  T-176 and T-179a remain open for physical-device acceptance.
- T-180: Weekly Review Keep and Undo now persist `confirmed` and `needs_review`
  even when no feedback row is generated. Repository tests cover empty-feedback
  transitions, queue membership after fresh queries, and status with a real
  feedback edit. Widget tests cover visible Keep/Undo behavior and the undo
  controller's single-use token contract. Awaiting independent review.
- Validation: focused repository/review tests 26/26; full Flutter suite
  786/786; `flutter analyze --no-pub` clean; `git diff --check` clean.
  GitNexus change analysis: 5 files, 8 symbols, LOW risk, no affected
  processes, no partial/truncated result.
- Published signed Android release `0.1.1+3` at the existing stable APK URL.
  The ARM64 artifact is 56,553,692 bytes (56.55 MB decimal), SHA-256
  `44fbae3736a939af1dfe707b8bd4675e50c2de715da308f380c65b98b4dbd940`.
  Signed install and explicit activity launch passed on the explicit ARM64 API
  35 emulator. The physical phone later reconnected and accepted `v2003` via
  `install -r`; signer, `firstInstallTime`, and data inodes were preserved, and
  Home opened populated. Exact transaction/review counts and T-176/T-179a
  physical acceptance remain unverified.
- Release metadata update was documentation-only; T-180 validation above is
  fresh for the current implementation.

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
