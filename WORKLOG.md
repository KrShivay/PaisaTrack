# Current Handoff

## 2026-09-28 — T-182 natural-language SMS fallback parsing

- Added conservative generic fallback evidence for completed charged,
  transferred-from, and added-to wording while keeping confidence review-only.
  Balance-only, OTP/promo/statement, decline/failure, refund/reversal, pending,
  scheduled, and future-tense payment messages abstain in the generic-only path.
  The balance guard preserves a completed debit followed by a balance or
  processing-fee amount.
- Added synthetic parser/cascade evidence tests, generic-only model-unavailable
  ingestion tests, bounded history tests, and explicit failed/reversal lifecycle
  routing fixtures. No sender filter, schema, cloud, or raw-SMS retention
  changes. Live provider LLM lifecycle safety remains open as P0 T-183.
- Independent review accepted. Validation: focused
  parser/cascade/lifecycle/ingestion/history and fixture suite 75/75; full
  Flutter suite 811/811; `flutter analyze --no-pub`, formatting, and
  `git diff --check` clean. GitNexus change analysis: 14 files, 15 symbols,
  0 affected processes, LOW risk, no partial/truncated result. Impact before
  edits was HIGH for the parser and CRITICAL for the cascade; warning was
  surfaced. No phone or backup access.

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
