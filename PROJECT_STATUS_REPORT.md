# PaisaTrack — Project Status Report
Reviewed 2026-07-05 by @claude, against PLAN.md, TASKS.md, and WORKLOG.md.

## 1. Where the project stands

PaisaTrack is in **Phase 0 (Foundation)** of the six-phase roadmap in PLAN.md, and correctly has not started Phase 1+ work — the plan explicitly says not to skip phases. Nothing in the codebase contradicts that discipline.

Done and reviewed: T-001 (repo scaffold), T-002 (Flutter/Android normalization — still technically "In Review," not yet reviewed), T-003 (Drift schema v1 + migration test), T-004 (Phase 0 grooming).

In progress but ahead of the task board: T-010 (Android Keystore passphrase provider) is fully coded and tested but the board still lists it as "Ready" (not started) with no WORKLOG entry — see §3.

Not started: T-005 (category seed loader), T-006 (Riverpod DB provider wiring), T-007 (fixture harness runner), T-008 (CI guardrails), T-009 (Phase 0 exit review).

**Estimate: Phase 0 is roughly 60–70% complete.** The hard parts (encrypted schema, migrations, native Keystore key management) are largely done; what's left is mostly wiring (Riverpod, seed loader) and process (fixture runner, CI hardening, exit review).

## 2. Code quality — what's good

- The seven Drift tables match PLAN.md §6.1 field-for-field, with sensible indexes on `transactions`.
- `openEncryptedDatabase` genuinely fails closed if SQLCipher isn't linked (checks `cipher_version` before setting the key), and both the host and Android integration migration tests assert real behavior (table/index names, `PRAGMA user_version`, live cipher check) rather than being vacuous.
- The new Android Keystore passphrase provider (`MainActivity.kt` + `AndroidKeystoreDatabasePassphraseProvider`) is a legitimate implementation: AES-GCM key wrapping via Android Keystore, StrongBox attempted with a fallback, passphrase generated once and reused. This directly satisfies PLAN.md §8's "SQLCipher key generated on first run, stored in Android Keystore" requirement — ahead of where the task board says the project is.
- Feature flags and thresholds live in `constants.dart` as PLAN.md §3 requires, not inlined.
- Docs (`schema.md`, `architecture.md`, `privacy.md`) are current for what's built so far.

## 3. Bugs and mistakes found

1. **Unhandled exception risk in the parser cascade.** `FieldNormalizer.parseAmount` throws `FormatException` when an amount capture is missing or malformed, and `_parseDirection`/`_parseChannel` throw on bad enum values. `TemplateMatcher.match` calls these with no try/catch, so a template that matches the sender/regex but has a malformed capture group will throw uncaught, bubbling out of `ParserCascade.parse`. PLAN.md §7.1 requires this to be a rejection ("Validation is code, not vibes: reject extraction..."), not a crash. No test currently exercises this path.
   Files: `lib/capture/template_engine/field_normalizer.dart`, `lib/capture/template_engine/template_matcher.dart`.

2. **Task board is stale relative to actual code.** T-010 (Keystore passphrase provider) is fully implemented in `lib/core/crypto/database_cipher.dart`, `android/.../MainActivity.kt`, and `test/core/crypto/database_cipher_test.dart` — but TASKS.md still lists it under "Ready" (not even "In Progress"), and there is no WORKLOG entry for it. COLLABORATION.md's own rule is that a session without a WORKLOG entry is incomplete. The new provider also isn't wired into `openEncryptedDatabase` yet, so it currently does nothing at runtime.

3. **`assets/seed/category_seed.json` is an empty `{}` stub.** T-005 (seed loader) depends on this file having real merchant→category mappings; right now it would load nothing.

4. **`assets/seed/categories.json` only has 6 of the 17 categories** listed in PLAN.md §5 (missing Shopping, Bills & Utilities, Subscriptions, Rent & Housing, EMI & Loans, Health, Education, Entertainment, Travel, Fees & Charges, Cash Withdrawal, Investments).

5. **README.md's "Current Status" section is stale** — it says Flutter/Dart aren't installed and runtime verification is blocked, but WORKLOG shows `flutter test`/`analyze`/`build apk` succeeding repeatedly since. Cosmetic, but misleading to a new reader.

## 4. Gaps against the plan's own testing strategy

- **No Kotlin JUnit tests exist at all**, despite PLAN.md §10 explicitly requiring them ("Kotlin: filter allowlist/rejection JUnit tests"). This matters most for `SmsFilter.kt` (junk/OTP filtering) and the new `DatabasePassphraseStore` (Keystore encrypt/decrypt logic) — the only test coverage for the latter is a Dart-side test with a mocked method channel, which doesn't exercise the actual Android Keystore/AES-GCM code at all.
- **No fixture harness runner yet** — `test/fixtures/sms/README.md` only documents the format; there's no code that scans `test/fixtures/sms/<bank>/` and compares output. This is T-007's job and hasn't started, so the "0 fixtures = clean report" acceptance criterion is unproven. Expected at this stage, just flagging it's still open.
- **CI doesn't check generated-code freshness or formatting** — `.github/workflows/ci.yml` runs `pub get` → `analyze` → `test` only; no `dart format --set-exit-if-changed`, no `build_runner` drift check. This is T-008's job, not started.

## 5. Recommended next steps (in order)

1. Fix the parser-cascade exception handling (bug #1) and add a test for a matched-but-malformed template — small, isolated, worth doing before more parser work builds on top of it.
2. Reconcile the task board: log T-010's actual state in WORKLOG.md, move it to In Progress/In Review as appropriate, and wire `AndroidKeystoreDatabasePassphraseProvider` into `openEncryptedDatabase` so the Keystore work is actually used at runtime (this can fold into T-006).
3. Populate `categories.json` (full 17) and give `category_seed.json` real content before T-005 lands.
4. Add Kotlin JUnit tests for `SmsFilter` and `DatabasePassphraseStore` — currently the only native code with zero native test coverage.
5. Proceed with T-007 (fixture harness) and T-008 (CI guardrails) as groomed, then T-009 (Phase 0 exit review) once T-005/006/007/008 land.

## 6. Bottom line

No architectural red flags. The schema, encryption approach, and parser design all conform to PLAN.md. The main risks are process drift (code outpacing the task board, which will cause confusion in a two-agent workflow that depends on the board being ground truth) and a couple of small robustness/data-completeness gaps that are cheap to fix now, before Phase 1 capture code starts depending on them.
