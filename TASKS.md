# Task Board
Last updated: 2026-07-05 by @claude

## In Progress

## Ready
<!-- Phase 1 — Capture MVP (PLAN.md §"Phase 1"). Ordered; each depends on the prior. -->
- [ ] T-020 (@codex) [P1] SMS permissions + onboarding flow
      AC: onboarding screen requests RECEIVE_SMS/READ_SMS with a plain-language rationale; denial is handled gracefully (app still opens, dev screen explains degraded state); permission state exposed via a Riverpod provider with test override; widget tests cover granted and denied branches with the platform channel faked. No raw SMS content touched in this task.
      Depends: T-006 review pass

- [ ] T-021 (@codex) [P1] Kotlin SMS BroadcastReceiver + sender filter
      AC: BroadcastReceiver handles SMS_RECEIVED_ACTION; SmsFilter allowlist accepts bank/UPI sender IDs and rejects OTP/promo/personal; raw SMS body is never written to logcat in release builds; JUnit tests cover allow and reject cases (subsumes the SmsFilter half of Proposed T-016).
      Depends: T-020 review pass

- [ ] T-022 (@codex) [P1] Platform channel: SMS → Dart ingestion
      AC: a platform channel delivers sanitized RawSms from Kotlin to Dart; Dart ingestion persists raw_sms then runs ParserCascade, writing a transaction on Ok and leaving raw_sms flagged unparsed on Err; a contract test proves receiver→channel→parser→DB with a fake channel over an in-memory AppDatabase.
      Depends: T-021 review pass, T-003 + T-005 + T-006 review pass

- [ ] T-023 (@codex) [P1] Historical SMS inbox backfill
      AC: on first permission grant, backfill reads the last N months from the SMS inbox via the platform channel, dedups against existing raw_sms, and processes through the cascade in chunks without blocking the UI thread; a test proves re-running backfill inserts no duplicate rows (idempotent).
      Depends: T-022 review pass

- [ ] T-024 (@codex) [P1] Real bank template registries + ≥30 sanitized fixtures/bank
      AC: template registries authored for the developer's own banks; ≥30 sanitized real SMS per bank committed under test/fixtures/sms/<bank>/ with expected JSON; SmsFixtureRunner asserts ≥90% parse into the correct NormalizedTransactionRecord and that declined/failed SMS produce err (no transaction). Supersedes Proposed T-017.
      Depends: T-022 review pass, T-007 review pass

- [ ] T-025 (@codex) [P1] Paired bank+wallet duplicate suppression
      AC: dedup logic suppresses a second transaction when a bank SMS and its paired wallet/UPI SMS describe the same debit (amount + counterparty within a time window); table-driven tests cover paired-duplicate, near-miss-not-duplicate, and unrelated cases.
      Depends: T-022 review pass

- [ ] T-026 (@codex) [P1] Transactions list + basic dashboard + unparsed dev screen
      AC: transactions list renders parsed transactions from the DB via Riverpod; a basic dashboard shows month totals by direction; a dev screen lists unparsed raw_sms; widget tests run over a seeded in-memory AppDatabase.
      Depends: T-022 review pass, T-006 review pass

- [ ] T-027 (@claude) [P1] Phase 1 exit review
      AC: verifies T-020..T-026 evidence against PLAN.md Phase 1 exit criteria (fresh-install ≥90% parse of last 3 months verified by hand vs bank statement; paired bank+wallet duplicates suppressed; unparsed messages visible in dev screen); writes a WORKLOG entry titled PHASE P1 EXIT REVIEW; lists any blockers before Phase 2 grooming.
      Depends: T-020, T-021, T-022, T-023, T-024, T-025, T-026 review pass

## Blocked

## In Review

## Done
- [x] T-019 (@codex under @human override, reviewed @claude) [P0] Pin Android minSdk to API 26 (2026-07-05)
      Done: android/app/build.gradle.kts now sets `minSdk = 26` (PLAN.md §2 Android 8.0) with a comment, replacing `flutter.minSdkVersion`. Caveat: `flutter build apk --debug` was NOT run here (flutter not on PATH in this environment) — build verification deferred to the next device/CI run; the Keystore/StrongBox code already runtime-guards on Build.VERSION_CODES.P so API 26 is safe.

- [x] T-009 (@claude) [P0] Phase 0 exit review (2026-07-05)
      Result: PASS — Phase 0 exit criteria met; see WORKLOG "PHASE P0 EXIT REVIEW". T-001..T-008 and T-010 all review-passed. No hard blockers before Phase 1 grooming. Carried follow-ups (non-blocking): T-016 (Kotlin unit tests), T-017 (fixture runner real fixtures), T-018 (CI stale-gen guard hardening), T-019 (pin minSdk=26 before SMS work).

- [x] T-008 (@codex, reviewed @claude) [P0] CI generated-code and integration-test guardrails (2026-07-05)
      Review: PASS — CI runs pub get → `build_runner build --delete-conflicting-outputs` → `git diff --exit-code -- lib/data/db/database.g.dart` → analyze → test; database.g.dart is git-tracked so the stale-generated-code guard is real (not vacuous). docs/development.md documents the Drift guard and the Android SQLCipher integration test as device-only/manual until a CI device runner exists. Matches AC. Note (non-blocking): guard watches only database.g.dart — broaden to all generated files as tables grow (tracked by T-018).

- [x] T-007 (@codex, reviewed @claude) [P0] Fixture harness formalization (2026-07-05)
      Review: PASS — SmsFixtureRunner scans test/fixtures/sms/<bank>/<case>.txt with matching <case>.expected.json; missing root reports no cases (Phase 0 empty-set is clean); sample sample/unparsed fixture round-trips to err:unparsed through parseFixtureCase. Tests assert both the empty-root and comparison paths — non-vacuous. Note (non-blocking): an orphan .txt without expected JSON throws StateError (strict-by-design); real committed fixtures still deferred to T-017.

- [x] T-006 (@codex, reviewed @claude) [P0] Database provider skeleton (2026-07-05)
      Review: PASS — ProviderScope installed at app root (main.dart); appDatabaseProvider opens AppDatabase through AndroidKeystoreDatabasePassphraseProvider → openEncryptedDatabase (the T-010 runtime wiring folded in here), disposes via ref.onDispose. Widget test overrides appDatabaseProvider with AppDatabase(NativeDatabase.memory()) and asserts boot + same(database). Matches AC. Note (non-blocking): the provider has no production UI consumer yet, so the real Keystore→SQLCipher path only exercises on device/Phase 1 — acceptable for a skeleton.

- [x] T-005 (@codex, reviewed @claude) [P0] Category seed loader + idempotency test (2026-07-05)
      Review: PASS — AppDatabase.seedDefaultCategories loads assets/seed/categories.json (asset registered in pubspec) via a batch insertOrIgnore, so reruns neither duplicate rows nor overwrite user-edited names/icons. Test seeds 18, renames food_dining, reseeds, and asserts count stays 18 with the user rename+icon preserved — proves both insert and idempotent-rerun. Matches AC.

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

- [ ] T-017 (@codex) [P0] Fixture harness runner follow-up — SUPERSEDED by T-024
      AC: formal fixture runner from T-007 is implemented after review-approved parser scope; no real SMS fixtures are committed
      Note: real-fixture work folded into Phase 1 T-024; keep only if a non-fixture runner enhancement emerges.
      Depends: T-007

- [ ] T-018 (@codex) [P0] CI generated-code and build_runner guards
      AC: CI fails when Drift generated code is stale and documents local build_runner regeneration command
      Depends: T-008
