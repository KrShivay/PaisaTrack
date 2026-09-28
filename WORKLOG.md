# Current Handoff

## 2026-09-28 — T-183 live SMS lifecycle guard

- Wired one local cue classifier into live capture, history import, and
  incremental catch-up. Non-transactional and unknown messages stop before
  extraction; failed, pending, and reversal records retain explicit lifecycle
  state and review status. The classifier preserves settled debit/credit with
  trailing balance context. A promotion footer yields to a specific account/card
  movement or an amount-led paid/spent/purchase phrase tied to a payee; generic
  reward copy such as “Rs 100 spent via UPI” remains a promotion. Model direction
  must agree with an explicit SMS debit/credit cue. A bare “purchase of … for
  Rs …” may disambiguate a balance message but does not override promotion
  cues because the wording is ambiguous. Unknown classification fails closed.
- Bumped the retained-SMS parser contract to version 2 so failures are retried
  under the new classifier by default. Added actual-provider adversarial and
  model-unavailable tests, plus history and catch-up provider tests. No sender
  filter, database schema, cloud, or raw-SMS retention changes. T-184 sender
  admission and T-185 durable “Not a transaction” remain separate backlog work.
- Validation: focused capture/lifecycle/history suite 57/57; full Flutter suite
  818/818; `flutter analyze --no-pub`, Dart format check, and `git diff --check`
  clean. GitNexus `detect-changes --scope all`: 12 files, 42 symbols, 13
  processes, HIGH risk. Refreshed index reports unrelated whole-flow truncation
  and cross-language unresolved property edges; earlier CRITICAL/UNKNOWN
  warning was surfaced. Independent review pending. No phone, archive, APK, or
  live SMS access.

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
