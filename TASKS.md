# Task Board
Last updated: 2026-07-05 by @claude

## In Progress

## Ready
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

## Done
- [x] T-010 (@codex, reviewed @claude) [P0] Android Keystore-backed passphrase provider (2026-07-05)
      Review: PASS — AndroidKeystoreDatabasePassphraseProvider + MainActivity DatabasePassphraseStore implement AES-GCM key-wrap via Android Keystore with StrongBox-when-available and a graceful fallback; passphrase generated once and reused; debug-gated reset via FLAG_DEBUGGABLE. Integration test asserts the real acceptance (same passphrase across restarts, fresh install differs) and the Dart test proves fail-closed on empty. On-device StrongBox/Keystore acceptance rests on the logged motorola_edge_50_pro run (I can't run a device here). Native-only unit coverage for the store is tracked by Proposed T-016; runtime wiring into openEncryptedDatabase folded into T-006.

- [x] T-002 (@codex, reviewed @claude) [P0] Flutter project normalization via `flutter create` (2026-07-05)
      Review: PASS — Android/Flutter platform files present and normalized to com.paisatrack (applicationId + namespace), repo docs not overwritten, .metadata/pubspec intact. Non-blocking follow-up filed as T-019: minSdk is still `flutter.minSdkVersion` (Flutter default), not pinned to API 26 as PLAN.md §2 requires — outside T-002's AC but must be set before Phase 1 SMS work.

- [x] T-001 (@codex, reviewed @claude) [P0] Repository foundation scaffold (2026-07-05)
      Review: PASS — PLAN/COLLABORATION/TASKS/WORKLOG present; docs stubs (architecture/schema/privacy/development) non-empty; parser fixture harness + fixture README present; CI workflow present. Matches AC.


- [x] T-015 (@codex, reviewed @claude) [P0] Refresh README Current Status (2026-07-05)
      Review: PASS — README "Current Status" no longer claims Flutter/Dart is uninstalled; it now states Phase 0 is in progress with repo-local Flutter, records that analyze/test/build apk pass, and notes the host SQLCipher migration skip plus device-tested Android migration. Accurate against WORKLOG.

- [x] T-014 (@codex, reviewed @claude) [P0] Reconcile Phase 0 board evidence (2026-07-05)
      Review: PASS — T-001/T-002/T-010 are marked `Review: PENDING @claude`, not self-approved; T-006 AC updated to fold in the Keystore→openEncryptedDatabase wiring; out-of-scope work correctly filed as Proposed T-016/T-017/T-018. Board now matches code reality.

- [x] T-013 (@codex, reviewed @claude) [P0] Complete category seed assets (2026-07-05)
      Review: PASS — categories.json holds all 18 PLAN.md §5 categories with unique ids and is_spending=false on Transfers/Cash Withdrawal/Income; category_seed.json has 21 entries and every value resolves to a real category id (no dangling refs, verified). seed_assets_test.dart asserts both taxonomy completeness and referential integrity — non-vacuous.

- [x] T-012 (@codex, reviewed @claude) [P0] Template date timestamps use UTC (2026-07-05)
      Review: PASS — FieldNormalizer.parseDate returns DateTime.utc; new test asserts isUtc and timezone-stable epoch ms. Note (non-blocking): the fallback path (sms.receivedAt) is still caller-supplied, and numeric-but-out-of-range dates roll over rather than reject — flagged for real-capture wiring / a future range guard.

- [x] T-011 (@codex, reviewed @claude) [P0] Parser rejects matched-but-malformed templates (2026-07-05)
      Review: PASS — TemplateMatcher.match wraps normalizeTemplateMatch in try/catch for FormatException and ArgumentError (covering parseAmount/parseOptionalAmount/parseDate and values.byName), continues past the bad template, and yields Err(ParseFailure.unparsed) per PLAN.md §7.1. Parametrized regression test covers non-positive amount, garbage amount, non-numeric date, and invalid direction. Note (non-blocking): `on ArgumentError` is broad but safe given the narrow try-body; revisit if normalizeTemplateMatch grows.

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

- [ ] T-019 (@codex) [P0] Pin Android minSdk to API 26
      AC: android/app/build.gradle.kts sets minSdk = 26 (PLAN.md §2 Android 8.0) instead of the Flutter default; `flutter build apk --debug` still succeeds
      Depends: T-002 review pass (done)
