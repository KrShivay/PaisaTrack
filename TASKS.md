# Task Board
Last updated: 2026-07-05 by @codex

## In Progress

## Ready
- [ ] T-012 (@codex) [P0] Template date timestamps use UTC
      AC: FieldNormalizer.parseDate returns DateTime.utc for parsed SMS dates; tests assert UTC equality and timezone-stable epoch milliseconds
      Depends: T-011

- [ ] T-013 (@codex) [P0] Complete category seed assets
      AC: assets/seed/categories.json contains every PLAN.md §5 default category with correct spending flags; assets/seed/category_seed.json contains a small documented merchant-to-category starter map; JSON validity test proves both seed files are well-formed and complete enough for T-005 loader work
      Depends: T-003 review pass

- [ ] T-014 (@codex) [P0] Reconcile Phase 0 board evidence
      AC: TASKS.md reflects true state for T-001, T-002, and T-010 from WORKLOG evidence without self-approving @claude reviews; WORKLOG records missing process entry and remaining review ownership
      Depends: none

- [ ] T-015 (@codex) [P0] Refresh README Current Status
      AC: README.md no longer claims Flutter/Dart verification is blocked; it summarizes current Phase 0 verification reality and repo-local Flutter usage
      Depends: none

- [ ] T-005 (@codex) [P0] Category seed loader + idempotency test
      AC: assets/seed/categories.json loads into Drift categories; rerunning seed does not duplicate rows or overwrite user-edited names/icons; test proves insert + rerun behavior
      Depends: T-003 review pass

- [ ] T-006 (@codex) [P0] Database provider skeleton
      AC: Riverpod ProviderScope is installed at app root; appDatabaseProvider exposes an AppDatabase opened through AndroidKeystoreDatabasePassphraseProvider on Android with test override support; widget/provider test proves app boots with fake/in-memory DB
      Depends: T-003 review pass

- [ ] T-007 (@codex) [P0] Fixture harness formalization
      AC: fixture runner scans test/fixtures/sms/<bank>/<case>.txt + <case>.expected.json; with zero real fixtures it reports no cases cleanly; sample unparsed fixture test proves parser output comparison path
      Depends: T-001 review pass

- [ ] T-008 (@codex) [P0] CI generated-code and integration-test guardrails
      AC: CI verifies generated Drift code is current after build_runner; normal unit tests run; Android SQLCipher integration test is documented as device-only/manual until CI device runner exists
      Depends: T-003 review pass

- [ ] T-009 (@claude) [P0] Phase 0 exit review
      AC: verifies T-001 through T-008 and T-010 evidence against PLAN.md Phase 0 exit criteria; writes WORKLOG entry titled PHASE P0 EXIT REVIEW; lists any remaining blockers before Phase 1 grooming
      Depends: T-001, T-002, T-003, T-005, T-006, T-007, T-008, T-010 review pass

## Blocked

## In Review
- [ ] T-011 (@codex -> review @claude) [P0] Parser rejects matched-but-malformed templates
      AC: TemplateMatcher treats normalizer validation/parse failures as expected misses; ParserCascade returns Err(ParseFailure.unparsed) for matching templates with non-positive amount, garbage amount, non-numeric date, or invalid direction; regression test covers all listed cases
      Evidence: GitNexus impact LOW for `TemplateMatcher.match` (1 direct caller: `ParserCascade.parse`; 1 affected process; 2 impacted symbols); `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk, parser/test/doc-only scope

- [ ] T-010 (@codex -> review @claude) [P0] Android Keystore-backed passphrase provider
      AC: passphrase generated on first run and stored in Android Keystore (StrongBox where available); openEncryptedDatabase is wired to the stored passphrase instead of a hardcoded test value; test proves the same passphrase is retrieved across app restarts and a fresh install gets a new one
      Evidence: `flutter test` passed; `flutter analyze --no-pub` clean; `flutter test integration_test/encrypted_database_migration_test.dart -d 192.168.1.10:5555` passed on motorola_edge_50_pro
      Impact: LOW — openEncryptedDatabase had 2 direct test callers across 2 DB test flows; DatabasePassphrase had 2 importing test files; MainActivity had no indexed upstream dependents

- [ ] T-001 (@codex -> review @claude) [P0] Repository foundation scaffold
      AC: PLAN/COLLABORATION/TASKS/WORKLOG exist; docs stubs exist; parser fixture harness exists; CI workflow exists
      Evidence: `flutter test` 5/5; `flutter analyze` clean; `flutter build apk --debug` built app-debug.apk

- [ ] T-002 (@codex -> review @claude) [P0] Flutter project normalization via `flutter create`
      AC: Android/Flutter platform files generated without overwriting repo docs; `flutter test` runs locally
      Evidence: Android SDK 36 doctor green; `flutter test` 5/5; `flutter analyze` clean; `flutter build apk --debug` built app-debug.apk

## Done
- [x] T-003 (@codex, reviewed @claude) [P0] Drift schema v1 + migration test (2026-07-05)
      Review: PASS — transactions/raw_sms/merchants/merchant_aliases/categories/rules/feedback match PLAN.md §6.1 field-for-field; host + Android integration migration tests assert real behavior (table/index names, PRAGMA user_version, live cipher_version) and fail closed when SQLCipher is unavailable; docs/schema.md updated with migration log entry. Follow-up: no task covered PLAN.md §8's Keystore-backed passphrase generation (opener currently takes a plain passphrase constant) — filed as T-010.

- [x] T-004 (@codex, reviewed @claude) [P0] Groom Phase 0 task breakdown (2026-07-05)
      Review: PASS — T-005 through T-009 are small, ordered, correctly dependency-linked to T-001/T-003, with testable AC covering DB seed, Riverpod skeleton, fixture harness, CI guardrails, and exit review. Process note: grooming was performed by @codex under an explicit @human override of the normal @claude-grooms-Ready rule (recorded in WORKLOG 19:10 entry) — no objection. Gap found and filed as T-010 (see above).

## Proposed
- [ ] T-016 (@codex) [P0] Kotlin unit tests for Android SMS and Keystore storage
      AC: native Kotlin/JUnit tests cover SmsFilter behavior and DatabasePassphraseStore persistence/error paths without relying on a physical device
      Depends: T-010 review pass

- [ ] T-017 (@codex) [P0] Fixture harness runner follow-up
      AC: formal fixture runner from T-007 is implemented after review-approved parser scope; no real SMS fixtures are committed
      Depends: T-007

- [ ] T-018 (@codex) [P0] CI generated-code and build_runner guards
      AC: CI fails when Drift generated code is stale and documents local build_runner regeneration command
      Depends: T-008
