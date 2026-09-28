# Current Handoff

## 2026-09-29 — T-184 verified SLICE SMS capture

- Added exact `SLICE` native sender admission. Synthetic native tests cover
  live and inbox filtering, plus rejection when `SLICE` appears only in an
  unknown sender's body signature.
- The generic parser now extracts the sample payee before the parenthesized UPI
  reference and uses a valid `on d-MMM-yy` date only when it occurs within the
  same short transaction clause after the payment verb. Unrelated footer dates
  and invalid calendar days retain the SMS receive time. Footer-only text is
  not parsed as a transaction. No schema, cloud, raw-SMS logging, or retention
  changes; T-162b remains separate. Synthetic data only; no device access.
- Validation: focused parser suite 16/16; full Flutter suite 821/821;
  `flutter analyze --no-pub`, Dart formatting, and `git diff --check` clean.
  Android `SmsFilterTest` and app Kotlin compilation passed with temporary
  Gradle 9.1 distribution after verifying its SHA-256. GitNexus impact before
  edits: SmsFilter.isAllowed LOW (2 direct callers; 1 flow), parser MEDIUM
  (8 direct callers; 2 test processes); SmsFilter class was UNKNOWN but text
  search confirmed its native paths. Change analysis: 16 symbols across 6 files,
  7 affected processes, HIGH risk; flows include parser/cascade ingestion,
  shadow pipeline, and test entrypoints. Independent review pending; no
  commit/push.

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
