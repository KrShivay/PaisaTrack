## 2026-07-06 23:50 @claude — Design system (dark-first) + theme implementation + screen retrofit

- Did: established the PaisaTrack design system per the human's direction (dark-first fintech anchored on the app icon: near-black green surfaces, emerald primary, gold accent; light as an equal derived variant) and retrofitted all existing screens.
- Docs: new `docs/design-system.md` — principles, color/typography/spacing/shape tokens, money & status semantics (debit/credit colors on amounts only, debit ≠ error, warning for degraded states), two-tier iconography (brand PNG illustrations hero-only; Material icons for UI; fixed per-category hues), motion, accessibility, component recipes, and a UI-PR review checklist. `docs/architecture.md` links it as binding.
- Code (new): `lib/core/theme/app_tokens.dart` (AppColorTokens/AppSpacing/AppRadius/AppDurations/AppIllustrations), `lib/core/theme/app_theme.dart` (Material 3 dark+light ThemeData from tokens; tonal surfaces, no shadows; tabular-figure helper for money text), `lib/core/theme/paisa_colors.dart` (ThemeExtension for credit/debit/warning/gold/info with brightness-aware fallback so bare-MaterialApp widget tests keep working), `lib/core/theme/category_visuals.dart` (seed icon-name → IconData, category-id → fixed hue, plus name→id normalizer for list rows that only carry categoryName).
- Code (retrofit, styling only — all test-visible strings and amount formats unchanged): `app.dart` (AppTheme light/dark, themeMode dark), dashboard (icon-tile summary cards, semantic colors, tabular amounts), transactions (design-system tile: category avatar, signed colored amount), home_shell (selected-icon variants), onboarding (hero illustration with errorBuilder fallback, warning-styled degraded notices instead of bare error text), unparsed dev screen (leading icon, secondary body style).
- Deliberately deferred: Indian digit grouping `formatInr()` (changes rendered strings → lands with widget-test updates in Phase 2); category_id/icon in `TransactionListItem` (repository query change, tracked as follow-up — name normalizer is the interim); PNG asset compression (~14 MB total at 1254×1254; resize ≤512px/WebP before Phase 5 release).
- Caveat: `flutter analyze` / `flutter test` NOT run here (no Flutter toolchain in this environment). Self-review covered imports, Dart 3.4 syntax, and Flutter 3.44 API availability (`withValues`, `CardThemeData`, `surfaceContainer*` verified present in `.tooling/flutter`), but run both locally plus `detect_changes()` before commit. Widget tests assert text finders only, so styling changes should be green, and onboarding's `Image.asset` has an errorBuilder guard.
- Next: local verification; then Phase 2 UI tasks (settings theme toggle switching themeMode to system, formatInr + test updates, empty-state redesigns per design-system §5).

## 2026-07-06 @codex — T-016

- Did: completed the native Kotlin/JUnit follow-up for SMS filter and Keystore passphrase storage. `SmsFilterTest` already covered the pure sender/body filter behavior. Added `DatabasePassphraseStoreTest` for persistence/error orchestration without a physical device: persisted encrypted passphrases are reused, debug reset clears storage plus cipher state and generates a fresh passphrase, and corrupted persisted ciphertext fails closed without overwriting storage.
- Code: extracted `DatabasePassphraseStore` from `MainActivity.kt` into `android/app/src/main/kotlin/com/paisatrack/DatabasePassphraseStore.kt`; production still uses SharedPreferences plus AndroidKeyStore/AES-GCM, while the store now accepts `PassphraseStorage`/`PassphraseCipher` collaborators for deterministic host JVM tests. Switched passphrase Base64 encoding to `java.util.Base64` so the core store logic is not blocked by Android framework stubs in unit tests.
- Files: `android/app/src/main/kotlin/com/paisatrack/MainActivity.kt`, `android/app/src/main/kotlin/com/paisatrack/DatabasePassphraseStore.kt`, `android/app/src/test/kotlin/com/paisatrack/DatabasePassphraseStoreTest.kt`, `TASKS.md`, `WORKLOG.md`.
- Evidence: GitNexus pre-edit impact on `DatabasePassphraseStore`, `DatabasePassphraseStore.getOrCreate`, and `MainActivity.configureFlutterEngine` was LOW. `./gradlew :app:testDebugUnitTest` BUILD SUCCESSFUL: `DatabasePassphraseStoreTest` 3/3 and `SmsFilterTest` 7/7, 0 failures/errors/skips.
- Caveat: host JUnit tests use fakes for storage/cipher orchestration; the real AndroidKeyStore provider remains covered by the prior T-010 device/integration evidence.
- Next: T-016 → Done. Phase 2 still waits on the T-027 manual fresh-install bank-statement reconciliation, or an explicit waiver.

## 2026-07-06 23:22 @claude — ADR 0002: remove cloud inference path (free/on-device-only)

- Did: implemented the human's decision that the project uses only free options — no paid or subscription services, especially for intelligence. Removed the optional cloud LLM fallback from the plan and codebase; all intelligence is now on-device with free open-weight components.
- Docs: PLAN.md updated (§1 core principle now "local-first, zero-cloud"; §2 Anthropic API row removed, on-device row expanded with free model options + optional in-app model download; §3 tree drops `cloud_extractor.dart`/`anonymizer.dart` and the `enableCloudFallback` flag; §4 cloud fallback feature removed, narratives marked on-device; §6.1 `parse_source` drops `'cloud'`; §7.1 cascade step 4 removed; §8 rewritten to "no cloud inference path exists"; §9 Phase 4 reworked to on-device-only with airplane-mode exit criterion; §10 anonymizer tests removed; §12 adds hard no-paid-dependency rule). New `docs/decisions/0002-no-cloud-services.md` records the decision as durable. `docs/privacy.md` and `.skills/intelligence-modules/SKILL.md` updated to match.
- Code: `lib/core/constants.dart` — removed unused `enableCloudFallback` (no code references existed; grep-verified across lib/test/android since the GitNexus MCP was unavailable in this session). `lib/data/models/normalized_transaction_record.dart` — removed `ParseSource.cloud` and its wire-name arm (only self-references existed; no fixture or test uses `'cloud'`). `lib/capture/parser_cascade.dart` — doc comment updated.
- Caveat: `flutter analyze` / `flutter test` NOT run here (no Flutter toolchain in this environment — repo `.tooling/flutter` is macOS-hosted). Both must be run locally before commit, plus `detect_changes()` per CLAUDE.md. `.claude/skills/intelligence-modules/SKILL.md` is write-protected in this session and still references `enableCloudFallback`/`cloud_extractor.dart` — sync it from `.skills/intelligence-modules/SKILL.md` locally.
- Next: local verification run, then this constraint is binding on Phase 4 grooming.

## 2026-07-06 23:13 @codex — PHASE P1 EXIT REVIEW (T-027)

- Result: REVIEW COMPLETE, EXIT NOT YET PASS. I reviewed T-020..T-026 plus T-028 against PLAN.md Phase 1 exit criteria: fresh install on phone parses >=90% of the last 3 months bank SMS into correct transactions verified by hand against bank statement; paired bank+wallet duplicates suppressed; unparsed messages visible in dev screen.
- Verified in source/tests: SMS permission/onboarding, native capture/filter, live Dart ingestion, inbox backfill, real template registry loading for live/backfill parsing, paired duplicate suppression, transaction list/dashboard, and unparsed dev screen all have implementation and regression coverage. `sms_bank_fixture_coverage_test.dart` proves 100% positive parse coverage across the committed real sanitized fixtures for Axis, IndusInd, Paytm Payments Bank, and SBI, with negative/declined/future-event fixtures rejected.
- Local evidence: `flutter analyze --no-pub` clean. Full `flutter test --no-pub --concurrency=1` passed: 57 passed, 2 skipped (one known host SQLCipher migration skip; one untracked scratch dashboard debug test intentionally skipped). A serial Phase 1-focused suite also passed: 49 tests. GitNexus `detect_changes(scope: all)` reported LOW risk, 3 changed files, 0 changed indexed symbols, 0 affected processes.
- Review cleanup: stabilized stream-backed widget tests that were hanging under `flutter test`. Dashboard, transaction-list, and unparsed-dev screen tests now override screen providers with fixed streams; Drift query behavior for newest-first ordering, soft-delete filtering, joined merchant/category display, and processed/unprocessed raw-SMS filtering is asserted in repository-level tests. The untracked scratch dashboard debug test is marked skipped rather than deleted.
- Blocker before Phase 2 grooming: I did not find explicit evidence that a fresh install on the phone parsed the last 3 months of bank SMS and was manually reconciled against a bank statement. The fixture suite is strong automated evidence, but it is not the same as the PLAN.md bank-statement reconciliation criterion. Run that device/manual pass and log the results before declaring Phase 1 exit PASS.
- Next: capture/log the manual fresh-install bank-statement reconciliation (or explicitly waive that criterion), then Phase 2 grooming can begin.

## 2026-07-06 22:20 @codex — T-028

- Did: wired the real bank template registries into production SMS parsing. `parserCascadeProvider` now loads `assets/templates/{axisbk,indusind,paytmb,sbi}.json` through `rootBundle`, parses them with `TemplateRegistry.fromJson`, and constructs `TemplateMatcher` with the resulting registries instead of `TemplateMatcher(registries: [])`.
- Live capture now waits until the async parser provider is ready before subscribing to the SMS stream. `smsBackfillProvider` awaits the same parser provider before constructing `SmsIngestor`, so live and backfilled SMS share the exact same real-template cascade.
- Added an end-to-end widget/provider regression in `test/capture/sms_ingestion_test.dart`: a real SBI fixture (`sbi_debit_dearupi_01`) is sent through `smsCaptureBootstrapProvider` and persists a parsed transaction matching the fixture's expected amount/direction/channel/merchant/account/ref/timestamp. Updated existing fake parser overrides in capture/backfill tests for the new async provider contract.
- Files: lib/capture/sms_ingestion.dart, lib/capture/sms_backfill.dart, test/capture/sms_ingestion_test.dart, test/capture/sms_backfill_test.dart, TASKS.md, WORKLOG.md
- Evidence: pre-edit GitNexus impact checks on `parserCascadeProvider` and `smsBackfillProvider` were LOW (0 direct callers, 0 affected processes/modules in the index). `flutter test --no-pub test/capture/sms_ingestion_test.dart test/capture/sms_backfill_test.dart` passed; `flutter analyze --no-pub` passed. Final `mcp__gitnexus__detect_changes(scope: all)` reported LOW risk with 0 affected processes. A full `flutter test --no-pub` run was started but interrupted after going quiet in later widget tests, so it is not counted as evidence.
- Next: T-028 → Done. T-027 Phase 1 exit review is the next Ready task.

## 2026-07-06 21:10 @claude — reconciliation + review — T-026, T-028 filed

- Did: reconciled the `Updated_code` working-copy git history (commits `afb8d6a`..`d9ee2cf`) into this repo. Content already matched byte-for-byte for 412/419 tracked files (hand-copied earlier but never committed); replayed the 7 real commits individually onto `main` with their original messages to keep history granularity (`bea1a06` FieldNormalizer date formats, `5c08965` T-024 templates+fixtures, `cdb2545` TASKS.md, `0bd43ac` AGENTS/CLAUDE sync, `1b124bb` skill defs, `e9c5912` Android Gradle fix, `d9ee2cf` T-025 duplicate suppression). Also found this repo's working tree already contained unrelated, uncommitted, further-along work (dashboard/transactions/dev screens + repositories, wired into `app.dart`) — committed that separately since it wasn't part of `Updated_code`.
- Reviewed the newly committed dashboard/transactions/dev-screen code (`TransactionRepository`, `RawSmsRepository`, `monthDirectionTotalsProvider`, `HomeShell`) — sound Riverpod wiring, correct null-safe fallbacks, matches T-026's AC. Moved T-026 to Done.
- Found a real defect while reviewing the capture path end-to-end: `parserCascadeProvider` (`lib/capture/sms_ingestion.dart`) and the parser `SmsBackfiller` reads (`lib/capture/sms_backfill.dart`) both construct `TemplateMatcher(registries: [])` — hardcoded empty. Nothing in `lib/` loads `assets/templates/{axisbk,indusind,paytmb,sbi}.json` (registered in `pubspec.yaml`, parsed only by the fixture-test harness) into the live parser. Every real SMS captured live or via backfill currently fails to parse regardless of T-024's 136 passing fixtures — this will fail T-027's ≥90%-parse exit criterion as-is. Filed as **T-028** in Ready, ahead of T-027, with T-027's Depends updated to include it.
- Files: TASKS.md, WORKLOG.md (no code changes this session beyond the reconciliation commits already made).
- Evidence: file-content diff confirmed 412/419 match before replay; no `flutter analyze`/`flutter test` run this session (no Flutter toolchain in this environment) — codex should verify both when picking up T-028.
- Next: T-028 (wire real templates into the live parser cascade) is the top Ready task; T-027 (Phase 1 exit review) follows once T-028 passes review.

## 2026-07-06 13:30 @claude (@human override, self-executed — no independent reviewer) — T-025

- Did: paired bank+wallet duplicate suppression. New `DuplicateSuppressor` (`lib/capture/duplicate_suppressor.dart`) flags a newly parsed transaction as a cross-source echo of an already-stored one when direction matches, amount matches within a small tolerance, timestamps fall within `AppConstants.duplicatePairWindowMinutes` (10 min), and either the UPI ref id matches or a normalized counterparty key (VPA local-part or merchant text, uppercased/alnum-only) matches or overlaps.
- Wired into `SmsIngestor.ingest`: before inserting a transaction, queries existing non-deleted transactions in the time window and marks the new row `isDeleted: true` on a match — raw SMS and the transaction row both still stored (auditable), just hidden from future list views. Shared by live capture and `SmsBackfiller`, so backfill-vs-live pairs are covered too.
- Also made `_transactionCompanionFor` fall back `merchantRaw` to `counterpartyVpa` when a template only captured a VPA (bank UPI-debit alerts) — the persisted schema has no separate VPA column, so without this fallback such rows carried no counterparty signal for matching at all.
- Files: lib/capture/duplicate_suppressor.dart (new), lib/capture/sms_ingestion.dart, lib/capture/sms_backfill.dart (doc comment only), lib/core/constants.dart, test/capture/duplicate_suppressor_test.dart (new), test/capture/sms_ingestion_test.dart, TASKS.md, WORKLOG.md
- Evidence: `flutter analyze` clean (1 pre-existing unrelated lint in `sms_backfill_test.dart`); `flutter test` 49 tests green (1 known-limitation SQLCipher-in-host-VM skip), including 7 table-driven `DuplicateSuppressor` cases (paired-duplicate, near-miss-not-duplicate, unrelated) and a new end-to-end `SmsIngestor` test driving a real bank SMS followed by a wallet echo; `mcp__gitnexus__impact(SmsIngestor, upstream)` → LOW risk before editing; `mcp__gitnexus__detect_changes(scope: all)` shows only the expected `SmsIngestor`/`smsBackfillProvider` symbols touched (medium risk, no surprises — expected since the shared ingest write path changed).
- Caveat: self-executed end-to-end by @claude at the human's direct request rather than an independent codex→claude review handoff, same pattern as T-024. The counterparty-matching heuristic (VPA-local-part vs merchant-text substring overlap) is untested against real paired bank+wallet SMS fixtures — none collected yet, since suppression logic is inherently approximate until real paired samples are available.
- Next: T-025 → Done. Ready queue now starts at T-026 (transactions list + dashboard + dev screen); T-027 (Phase 1 exit review) still depends on T-025 being trusted end-to-end — flag for review pass alongside T-024.

## 2026-07-06 10:00 @claude (@human override, self-executed — no independent reviewer) — T-024

- Did: authored real bank template registries + sanitized fixtures for all 4 of the developer's own banks. `assets/templates/{indusind,sbi,paytmb,axisbk}.json` — sender patterns plus named-group regex templates for UPI debit/credit, netbanking/ACH, card-spend, and card-payment-received shapes. All real SMS pulled directly off the developer's own Android device via `adb`, never fabricated; sanitized per the `sms-template-authoring` skill (§5): personal counterparty names (including the device owner's own name) masked to fixed placeholders, account/card digits masked to fixed placeholders, business/merchant names left unmasked, exact bank formatting/punctuation preserved.
- Fixtures: `test/fixtures/sms/{indusind,sbi,paytmb,axisbk}/` — 136 total (30-44/bank), each a `.txt` body + hand-computed `.expected.json`. Followed the fixture-first law (≥5 real fixtures per template, at least one negative); shapes with <5 real occurrences (SBI credit-reversal ×2, Paytm's one-off "Automatic Payment... done" message) committed as negative "known gap" fixtures rather than templated or fabricated.
- New `sms_bank_fixture_coverage_test.dart` loads all 4 registries off disk and asserts ≥90% per-bank positive-fixture match ratio (`jsonEncode(actual) == jsonEncode(fixture.expected)`, chosen over `mapEquals` after finding a shallow-equality bug there) and that every negative fixture resolves to `err` — all 4 banks hit 100%.
- Extended `FieldNormalizer.parseDate` (`lib/capture/template_engine/field_normalizer.dart`) with `dd-MM-yyyy` (Paytm) and separator-less alpha-month `ddMMMyy` (SBI, e.g. `08Oct23`) support, needed by real bank date formats; 3 new unit tests in `field_normalizer_test.dart` (6/6 passing).
- Rewrote `docs/sms-templates.md` from a near-empty stub into one section per bank documenting sender patterns, template shapes, date formats, and known gaps/normalizer traps.
- Extraction note: an early Python raw-dump split on every newline fragmented Axis Bank's genuinely multiline "Spent..." SMS bodies into garbled fake rows; fixed by re-splitting on `re.split(r'(?=Row: \d+ address=)', raw)` so each device row (with embedded newlines) stays intact.
- Files: assets/templates/{indusind,sbi,paytmb,axisbk}.json (new), test/fixtures/sms/{indusind,sbi,paytmb,axisbk}/* (new, 136 fixtures), test/fixtures/sms_bank_fixture_coverage_test.dart (new), lib/capture/template_engine/field_normalizer.dart, test/capture/template_engine/field_normalizer_test.dart, docs/sms-templates.md, TASKS.md, WORKLOG.md
- Evidence: `flutter analyze` clean (1 pre-existing unrelated lint); full `flutter test` suite green (41+ tests, 1 known-limitation SQLCipher-in-host-VM skip); `mcp__gitnexus__detect_changes(scope: all)` shows only the expected `FieldNormalizer` symbols touched (medium risk, no surprises).
- Caveat: self-executed end-to-end by @claude at the human's direct request rather than an independent codex→claude review handoff — flagging for a future independent review pass before this is fully trusted for production parsing; the counterparty-matching groundwork here is what T-025's dedup heuristic later builds on.
- Next: T-024 → Done. @codex next Ready task is T-025 (paired bank+wallet duplicate suppression).

## 2026-07-05 23:40 @claude (@human override waiving no-self-approval) — T-023 implement + REVIEW (PASS)

- Context: continuing the option-2 stretch where the @human authorized @claude to both implement (as @codex) and review. Implemented T-023, then reviewed adversarially — the review found and fixed a real duplicate-transaction defect before finalizing (below).
- Did (implement): historical SMS inbox backfill.
  - Native: new `com.paisatrack/sms_backfill` MethodChannel with `readInbox(sinceEpochMillis)`, `isBackfillComplete`, `markBackfillComplete`. `SmsInboxReader` queries `Telephony.Sms.Inbox` (ADDRESS/BODY/DATE), applies the existing `SmsFilter`, and stamps each row with the shared `CapturedSmsId` — extracted from `SmsReceiver.kt` into `CapturedSmsId.kt` so live capture and backfill hash identically. The query runs on a background `ExecutorService` (inbox can be large) and posts back on the main looper; `readInbox` is gated on READ_SMS being granted. `BackfillStateStore` persists the run-once flag in SharedPreferences. Never logs bodies; errors return no message content.
  - Dart: `SmsInboxReader`/`PlatformSmsInboxReader`, `BackfillMarker`/`PlatformBackfillMarker`, and `SmsBackfiller` (reads last `AppConstants.smsBackfillMonths` = 3 months, ingests via the existing `SmsIngestor.ingest` in `smsBackfillChunkSize` = 25 chunks, yielding `Future.delayed(Duration.zero)` between chunks so the UI thread never blocks; per-message failures absorbed without logging). `smsBackfillProvider` (FutureProvider) runs it once when permission==granted and the DB is ready, guarded by the persisted marker, and marks complete after. Shared `decodeRawSmsPayload` extracted in `captured_sms_source.dart` so live + backfill validate payloads identically. `app.dart` watches the provider.
- Review defect found + fixed: the first cut gated the run only with the FutureProvider cache (once per process). Because live capture stamps ids from `System.currentTimeMillis()` while backfill stamps from the inbox `DATE`, the two paths produce different ids for the same message — so re-running on every cold start would re-insert every already-live-captured message under a new id, duplicating transactions each launch. AC "dedups against existing raw_sms" was therefore not met. Fixed with the persisted `BackfillMarker` (native SharedPreferences) so backfill fires only on the genuine first grant, before any live captures exist. No schema migration — the reviewed T-003 schema is untouched.
- Verified (repo-local SDK, unsandboxed, HOME→.tooling/_home): `flutter analyze lib test/capture` clean; `flutter test` → 36 passed / 1 host SQLCipher skip; new `test/capture/sms_backfill_test.dart` 6/6 (backfill into raw_sms+transactions; **re-running inserts no duplicate rows — the AC test**; dedups an already-present id; crosses chunk boundaries; provider runs once + marks complete; provider skips when marker already complete). Gradle `:app:testDebugUnitTest` → BUILD SUCCESSFUL, `:app:compileDebugKotlin` recompiled the new native surface, SmsFilterTest still green.
- Impact preflight: `PlatformCapturedSmsSource` upstream MEDIUM but confined to the Capture module (tests + `sms_ingestion.dart`), no execution flows — the `decodeRawSmsPayload` extraction is additive; `smsCaptureBootstrapProvider` LOW (added a sibling provider, unchanged). No HIGH/CRITICAL.
- Files: android/.../MainActivity.kt, android/.../capture/CapturedSmsId.kt (new), android/.../capture/SmsInboxReader.kt (new), android/.../capture/SmsReceiver.kt, lib/capture/sms_backfill.dart (new), lib/capture/captured_sms_source.dart, lib/core/constants.dart, lib/app.dart, test/capture/sms_backfill_test.dart (new), docs/privacy.md, README.md, TASKS.md, WORKLOG.md
- Non-blocking boundaries logged: (a) live-vs-backfill *semantic* duplicates (a bank SMS and its wallet echo of the same debit) are not suppressed here — that is T-025's job; the run-once marker keeps the overlap window to grant→first-scan; (b) backfill is one-time by design (AC "on first permission grant"), so messages missed *after* the first grant while the receiver is inactive are not re-swept — revisit if a periodic catch-up is wanted, but it must first unify identity or use T-025 dedup to stay duplicate-free; (c) `SmsInboxReader` reads `Telephony.Sms.Inbox` only (received messages), which is correct for transactional alerts.
- Review verdict: T-023 → PASS. Next: @codex next Ready task is T-024 (real bank template registries + ≥30 sanitized fixtures/bank) — needs the developer's real sanitized SMS.


- Context: the @human explicitly authorized @claude to both implement (as @codex) and review this Phase 1 stretch, knowingly waiving the COLLABORATION.md "@claude must not self-approve" rule. Reviews below were written adversarially — hunting for defects, verifying against source, and re-running the suites rather than trusting prior evidence.
- Verified (repo-local SDK, unsandboxed): `flutter analyze` clean; `flutter test test/capture/ test/widget_test.dart test/features/` → 21/21 (now 22/22 after the added idempotency test); Gradle `:app:testDebugUnitTest` → BUILD SUCCESSFUL (SmsFilterTest 7/7, live EventChannel bridge compiles).
- T-020 → PASS. Permission gate/provider/onboarding branch handling all sound; Keystore passphrase logic confirmed byte-unchanged. Non-blocking: cold `status()` reports only granted/denied (permanentlyDenied is post-request only) — UI handles the transition.
- T-021 → PASS. `SmsFilter` framework-free and JVM-tested; `SmsReceiver` never logs bodies; manifest receiver gated by BROADCAST_SMS. Non-blocking: allowlist is first-pass (hardened in T-024); multipart joined in group order.
- T-022 → PASS, with two fixes applied during review:
  1. Robustness bug: `unawaited(ingestor.ingest(sms))` let a DB-write failure escape as an unhandled async/zone error (the stream `onError` only catches decode failures, not the detached future). Routed through a new `_ingestSafely` that absorbs the failure — capture stream stays alive, message is recovered by T-023 backfill, no body logged.
  2. The WORKLOG claimed "idempotent reprocessing" with no test proving it. Added a duplicate-id contract test: feeding the same payload twice yields exactly one `raw_sms` and one `txn_<id>` row (insertOnConflictUpdate). 3/3 capture tests green.
- Files: lib/capture/sms_ingestion.dart, test/capture/sms_ingestion_test.dart, TASKS.md, WORKLOG.md
- Non-blocking boundaries logged for T-022: (a) SMS arriving while the app process is dead hit the no-op `CapturedSmsSink` and are dropped at this layer — by design, recovered by T-023 inbox backfill; (b) `ParserCascade` runs inside the write transaction — fine for the current fast template matcher, revisit if the cascade becomes async/heavy in T-024.
- Housekeeping: removed stray tool-state dirs (`.config/`, `.dartServer/`, `.flutter`, `.dart-tool/`) that unsandboxed `flutter` created inside the repo (redirected HOME) so they can't be committed.
- Next: T-020/T-021/T-022 → Done. @codex next Ready task is T-023 (historical inbox backfill).

## 2026-07-05 22:41 @codex — T-022
- Did: wired the live SMS bridge from Android into Dart. MainActivity now exposes `com.paisatrack/sms_events` as an EventChannel-backed `CapturedSmsSink`; SmsReceiver forwards approved SMS with deterministic SHA-256 ids; Dart boots capture from `smsCaptureBootstrapProvider` once SMS permission and `appDatabaseProvider` are both ready, persists `raw_sms`, runs `ParserCascade`, writes one `transactions` row on `Ok`, and leaves `processed=false` on `Err`. Moved T-022 Ready→In Review.
- Files: android/app/src/main/kotlin/com/paisatrack/MainActivity.kt, android/app/src/main/kotlin/com/paisatrack/capture/SmsReceiver.kt, lib/capture/captured_sms_source.dart, lib/capture/sms_ingestion.dart, lib/app.dart, test/capture/sms_ingestion_test.dart, test/support/fake_captured_sms_source.dart, test/widget_test.dart, README.md, TASKS.md, docs/architecture.md, WORKLOG.md
- Evidence: `impact` preflight stayed LOW for `CapturedSmsSink`, `SmsReceiver`, `MainActivity`, `PaisaTrackApp`, and `ParserCascade`; I explicitly avoided editing `AppDatabase` after `impact` reported HIGH blast radius there. `flutter analyze` passed. Unsandboxed `flutter test test/capture/sms_ingestion_test.dart test/widget_test.dart` passed (4/4). Unsandboxed Gradle `:app:testDebugUnitTest` passed and compiled the new EventChannel bridge (`:app:compileDebugKotlin`, `:app:testDebugUnitTest`). `detect_changes(scope: "all")` reported MEDIUM risk, with affected indexed flows limited to the existing `configureFlutterEngine`/database-passphrase process because the live bridge was added inside `MainActivity`.
- Decisions: kept ingestion logic out of `AppDatabase` to avoid widening blast radius; used an EventChannel + injectable `CapturedSmsChannel` seam so tests can fake the channel directly; made transaction ids deterministic (`txn_<smsId>`) so reprocessing one raw SMS stays idempotent at this layer.
- Open questions: app-killed/background delivery semantics are still partially deferred to T-023 backfill; current live capture reliably handles the running-process case and drains any in-memory events once Flutter attaches.
- Next: @claude review T-020/T-021/T-022; @codex next Ready task is T-023 (historical inbox backfill).

## 2026-07-06 00:45 @codex (via @claude, @human override) — T-021
- Did: added Kotlin SMS capture front door. SmsFilter (pure-Kotlin allowlist: known bank/UPI DLT sender tokens; rejects OTP/promo markers and personal numbers). SmsReceiver (BroadcastReceiver on SMS_RECEIVED, reassembles multipart bodies per sender, filters, forwards accepted CapturedSms to a swappable CapturedSmsSink defaulting to no-op; never logs bodies). Registered the receiver in AndroidManifest with BROADCAST_SMS permission. Added JUnit deps + SmsFilterTest. Moved T-021 Ready→In Review.
- Files: android/app/src/main/kotlin/com/paisatrack/capture/SmsFilter.kt, android/app/src/main/kotlin/com/paisatrack/capture/SmsReceiver.kt, android/app/src/test/kotlin/com/paisatrack/capture/SmsFilterTest.kt, android/app/src/main/AndroidManifest.xml, android/app/build.gradle.kts, TASKS.md, WORKLOG.md
- Evidence: `./gradlew :app:testDebugUnitTest` (JAVA_HOME zulu-17, sdk.dir from local.properties) → BUILD SUCCESSFUL in 16s. SmsFilterTest: tests=7 skipped=0 failures=0 errors=0 (report build/app/test-results/testDebugUnitTest/TEST-com.paisatrack.capture.SmsFilterTest.xml). The same build ran compileDebugKotlin over the whole app module, so T-020's MainActivity permission channel also compiles clean. Dart side unchanged (analyze/test already green).
- Decisions: SmsFilter is framework-free so it's JVM-unit-testable without Robolectric; token allowlist is a first pass to be refined against real fixtures in T-024; receiver→Dart delivery deliberately deferred to T-022 (sink is a no-op seam now). This subsumes the SmsFilter half of Proposed T-016; the DatabasePassphraseStore native tests still belong to T-016.
- Open questions: sink→platform-channel wiring and app-killed delivery semantics are T-022 design points.
- Process note: T-020 and T-021 are stacked in In Review ahead of an independent @claude review (I implemented both under the @human "keep proceeding" override; I am not self-approving them to Done).
- Next: @claude review T-020 + T-021; @codex next Ready task is T-022 (platform channel SMS→Dart ingestion).

## 2026-07-06 00:20 @codex (via @claude, @human override) — T-020
- Did: implemented SMS permissions + onboarding. Added SmsPermissionGate/PlatformSmsPermissionGate over channel `com.paisatrack/sms_permissions`; smsPermissionControllerProvider (AsyncNotifier reading status on build, request() publishing outcome); OnboardingScreen (rationale + grant button + graceful denied/permanentlyDenied/error states) wired as app home; MainActivity now serves the permission channel and resolves status/request via onRequestPermissionsResult; RECEIVE_SMS/READ_SMS added to AndroidManifest. Moved T-020 Ready→In Review.
- Files: lib/capture/permissions/sms_permission.dart, lib/capture/permissions/sms_permission_provider.dart, lib/features/onboarding/onboarding_screen.dart, lib/app.dart, android/app/src/main/kotlin/com/paisatrack/MainActivity.kt, android/app/src/main/AndroidManifest.xml, docs/architecture.md, test/support/fake_sms_permission_gate.dart, test/capture/permissions/sms_permission_provider_test.dart, test/features/onboarding/onboarding_screen_test.dart, test/widget_test.dart, TASKS.md, WORKLOG.md
- Evidence: ran the repo-local SDK (.tooling/flutter) — `flutter analyze` clean; `flutter test` 27 passed / 1 host SQLCipher skip. New coverage: 6 provider tests (build status, request→granted, request→permanentlyDenied, build-error AsyncError, fromName mapping) + 4 onboarding widget tests (granted, denied→tap→granted, permanentlyDenied→settings, status-error→retry). Updated widget_test to wrap in ProviderScope with a fake gate.
- Decisions: used a platform channel (no permission_handler dep) to match the existing database_passphrase pattern; permanentlyDenied inferred from !shouldShowRequestPermissionRationale after denial; onboarding is app home so first run prompts. Native Kotlin path is device-only here — JUnit coverage stays in T-016.
- Correction to prior entries: this repo DOES ship a working Flutter SDK at .tooling/flutter; earlier "flutter not on PATH, can't verify" caveats were wrong. From here I verify with the repo-local SDK.
- Open questions: none.
- Next: @claude review T-020; @codex next Ready task is T-021 (Kotlin BroadcastReceiver + SmsFilter).

## 2026-07-05 23:55 @claude/@codex — T-019 + Phase 1 grooming (open Phase 1)
- Did (T-019, @codex under explicit @human override): pinned `minSdk = 26` in android/app/build.gradle.kts (PLAN.md §2 Android 8.0), replacing `flutter.minSdkVersion`; moved T-019 Proposed→Done.
- Did (Phase 1 grooming, @claude): broke PLAN.md §"Phase 1 — Capture MVP" into ordered tasks T-020..T-027 in Ready, each with testable AC and dependency links: T-020 SMS permissions + onboarding, T-021 Kotlin BroadcastReceiver + SmsFilter, T-022 platform channel SMS→Dart ingestion, T-023 inbox backfill, T-024 real registries + ≥30 sanitized fixtures/bank (≥90% parse), T-025 paired bank+wallet dedup, T-026 transactions list + dashboard + unparsed dev screen, T-027 @claude Phase 1 exit review. Marked Proposed T-017 SUPERSEDED by T-024.
- Files: android/app/build.gradle.kts, TASKS.md, WORKLOG.md
- Evidence: staged `detect_changes` LOW (docs + one Gradle constant; no indexed code symbols affected). `impact` not applicable to a Gradle config constant (not a graph symbol).
- Caveat: `flutter build apk --debug` NOT run (flutter/dart not on PATH here) — T-019 build verification deferred to next device/CI run; Keystore/StrongBox path already runtime-guards on Build.VERSION_CODES.P, so API 26 is safe.
- Decisions: grooming assigns implementation to @codex and review to @claude per COLLABORATION.md; privacy AC baked into T-021/T-022 (no raw SMS in release logs). Left T-016/T-018 in Proposed as still-valid follow-ups.
- Open questions: T-024 needs the developer's own real (sanitized) bank SMS to author registries — that input is a human/device step.
- Next: @codex to take T-020 (SMS permissions + onboarding), the first Ready Phase 1 task; @claude reviews.

## 2026-07-05 23:40 @claude — PHASE P0 EXIT REVIEW (T-009)
- Did: performed the Phase 0 exit review against PLAN.md §"Phase 0 — Foundation" exit criteria (line 387), now that every dependency (T-001, T-002, T-003, T-005, T-006, T-007, T-008, T-010) has a recorded @claude review PASS.
- Exit criteria verdict:
  1. `flutter test` green in CI — MET. .github/workflows/ci.yml runs pub get → build_runner stale-code guard → analyze → test on push/PR. @codex logs green analyze+test across T-005..T-008; database.g.dart is git-tracked so the guard is non-vacuous.
  2. Encrypted DB creates and migrates — MET. T-003 Drift schema v1 + migration test (host fails-closed when SQLCipher absent; Android integration test asserts real cipher_version + all 7 tables), T-010 Android Keystore AES-GCM passphrase wrap (device-verified on motorola_edge_50_pro), wired into runtime via T-006 appDatabaseProvider → openEncryptedDatabase.
  3. Fixture runner loads fixtures and asserts parser output (0 templates ⇒ all unparsed; the harness is what's proven) — MET. T-007 SmsFixtureRunner scans <bank>/<case>.txt+expected.json, empty root reports no cases, sample/unparsed fixture round-trips to err:unparsed.
- Result: PASS. Phase 0 foundation is complete and its exit criteria are proven by tests. No hard blockers to Phase 1 grooming.
- Carried non-blocking follow-ups (Proposed, groom before/into Phase 1): T-019 pin android minSdk=26 (PLAN §2) — REQUIRED before Phase 1 SMS work; T-016 native Kotlin unit tests for SmsFilter/DatabasePassphraseStore; T-017 real fixture runner content; T-018 broaden CI stale-generated-code guard.
- Caveat: flutter/dart are not on my PATH, so criterion (1) and device criteria rest on @codex's logged runs + my source/CI reading, not fresh local execution — consistent with all prior @claude reviews this phase.
- Files: TASKS.md, WORKLOG.md
- Next: @codex to groom/take T-019 (minSdk) and begin Phase 1 template/capture work per PLAN.md §"Phase 1"; @claude reviews.

## 2026-07-05 23:35 @claude — review T-005/T-006/T-007/T-008
- Did: reviewed the four Phase 0 @codex tasks against their AC and source; all PASS. Moved T-005..T-008 from In Review to Done with review notes.
- T-005: AppDatabase.seedDefaultCategories loads assets/seed/categories.json (asset registered in pubspec) via batch insertOrIgnore → idempotent, preserves user-edited name/icon; test seeds 18, renames food_dining, reseeds, asserts count stays 18 and rename survives (non-vacuous).
- T-006: ProviderScope at root; appDatabaseProvider opens AppDatabase through AndroidKeystoreDatabasePassphraseProvider → openEncryptedDatabase with ref.onDispose; widget test overrides with NativeDatabase.memory() and asserts boot + same(database). Note: no production UI consumer yet (skeleton).
- T-007: SmsFixtureRunner scans <bank>/<case>.txt+expected.json; empty root → no cases; sample/unparsed → err:unparsed; both paths tested. Note: orphan .txt without expected JSON throws StateError (strict-by-design).
- T-008: CI guard is real — database.g.dart git-tracked, git diff --exit-code after build_runner; analyze+test run; docs/development.md documents Drift guard + device-only integration test.
- Caveat: could not run flutter/dart locally (not on PATH); relied on source + CI-file reading + @codex's logged green analyze/test/build_runner and staged detect_changes LOW.
- Files: TASKS.md, WORKLOG.md

## 2026-07-05 23:12 @codex — T-008
- Did: added CI guardrail that runs build_runner and fails if `lib/data/db/database.g.dart` changes; documented normal CI checks and Android SQLCipher integration as device-only/manual until CI has a device runner; moved T-008 to In Review for @claude.
- Files: .github/workflows/ci.yml, docs/development.md, TASKS.md, WORKLOG.md
- Evidence: `dart run build_runner build --delete-conflicting-outputs` succeeded (drift_dev emitted a non-failing analyzer-version warning); `git diff --exit-code -- lib/data/db/database.g.dart` passed; `flutter analyze` clean; `flutter test` passed with existing host SQLCipher skip; staged `detect_changes` LOW on intended T-008 files.
- Decisions: CI continues to run normal host unit tests only; Android SQLCipher integration test remains manual/device-only and must be logged in WORKLOG until a CI device runner exists. Did not implement the broader Proposed T-018 follow-up beyond T-008 AC.
- Open questions: none
- Next: @claude review T-005/T-006/T-007/T-008; T-009 Phase 0 exit review can proceed after those reviews pass.

## 2026-07-05 22:58 @codex — T-007
- Did: added SMS fixture runner that scans `test/fixtures/sms/<bank>/<case>.txt` plus matching expected JSON; added empty-root test and synthetic sample unparsed fixture proving parser output comparison; moved T-007 to In Review for @claude.
- Files: test/fixtures/sms_fixture_runner.dart, test/fixtures/sms_fixture_runner_test.dart, test/fixtures/sms/sample/unparsed.txt, test/fixtures/sms/sample/unparsed.expected.json, test/fixtures/sms/README.md, docs/development.md, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact LOW for `ParserCascade` (2 direct dependents, 1 test process) and `ParserCascade.parse` (1 direct caller, 1 test process); focused `flutter test test/fixtures/sms_fixture_runner_test.dart` passed; `flutter analyze` clean; `flutter test` passed with existing host SQLCipher skip; staged `detect_changes` LOW on intended T-007 files.
- Decisions: used one synthetic sanitized unparsed sample rather than real bank SMS; expected JSON supports both `ok` normalized records and `err` parse failures; did not implement the larger T-017 fixture runner follow-up.
- Open questions: none
- Next: @claude review T-005/T-006/T-007; @codex next Ready task is T-008.

## 2026-07-05 22:38 @codex — T-006
- Did: installed Riverpod `ProviderScope` at app root; added `appDatabaseProvider` plus overrideable passphrase and directory providers; wired production database open through `AndroidKeystoreDatabasePassphraseProvider` and `openEncryptedDatabase`; added widget/provider test booting app with in-memory DB override; moved T-006 to In Review for @claude.
- Files: lib/main.dart, lib/data/db/database_provider.dart, test/widget_test.dart, docs/architecture.md, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact LOW for `main` (0 direct callers, 0 processes), `PaisaTrackApp` (2 direct importers, 0 processes), and `openEncryptedDatabase` (2 direct test callers, 2 test processes); focused `flutter test test/widget_test.dart` passed; `flutter analyze` clean; `flutter test` passed with existing host SQLCipher skip; staged `detect_changes` LOW on intended T-006 files.
- Decisions: kept database creation async via Riverpod; used provider overrides for fake/in-memory DB tests; did not add repository screens or Phase 1 SMS work.
- Open questions: none
- Next: @claude review T-005/T-006; @codex next Ready task is T-007.

## 2026-07-05 22:20 @codex — T-005
- Did: added bundled category seed loader on `AppDatabase` using insert-or-ignore semantics; added DB idempotency test proving first load inserts categories and rerun preserves user-edited category name/icon; moved T-005 to In Review for @claude.
- Files: lib/data/db/database.dart, test/data/db/category_seed_loader_test.dart, docs/seed-assets.md, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact LOW for `AppDatabase` (direct callers: DB migration test and Android integration migration test); focused `flutter test test/data/db/category_seed_loader_test.dart` passed; `flutter analyze` clean; `flutter test` passed with existing host SQLCipher skip; staged `detect_changes` LOW on intended T-005 files.
- Decisions: kept T-005 scoped to loading `assets/seed/categories.json` into Drift only; did not implement merchant category seed consumption or T-006/T-007/T-008/T-019 work.
- Open questions: none
- Next: @claude review T-005; @codex can pick T-006 after review flow allows or continue Ready queue if @human wants parallel Phase 0 progress.

## 2026-07-05 21:55 @claude — Review T-001, T-002, T-010; T-009 status
- Did: completed the remaining pending @claude reviews (T-001 scaffold, T-002 Flutter/Android normalization, T-010 Keystore passphrase provider) and assessed T-009 (Phase 0 exit review) readiness
- Files: TASKS.md, WORKLOG.md
- Evidence: verified T-001 artifacts (PLAN/COLLABORATION/TASKS/WORKLOG, non-empty docs stubs, fixture harness + README, CI workflow) all present; T-002 android/app/build.gradle.kts applicationId + namespace = com.paisatrack, platform files present, docs not overwritten; T-010 read lib/core/crypto/database_cipher.dart, android/.../MainActivity.kt, test/core/crypto/database_cipher_test.dart, integration_test/encrypted_database_migration_test.dart — integration test asserts stable-across-restarts + fresh-install-differs, Dart test asserts fail-closed on empty. Could not run `flutter`/`dart` (not on PATH); relied on source + @codex's logged device run (motorola_edge_50_pro) and GitNexus impact/detect_changes evidence.
- Decisions: T-001 PASS, T-002 PASS, T-010 PASS — all moved to Done. Non-blocking gap found in T-002: minSdk is still the Flutter default, not PLAN.md §2's API 26 — filed as Proposed T-019. T-010's on-device StrongBox acceptance rests on the logged device run, not a fresh run here.
- T-009 (Phase 0 exit review): CANNOT PASS YET. Its dependencies T-005 (seed loader), T-006 (Riverpod DB provider + Keystore wiring), T-007 (fixture runner), T-008 (CI guards) are not started, so PLAN.md Phase 0 exit criteria ("flutter test green in CI; encrypted DB creates and migrates; fixture runner loads fixtures and asserts parser output") are not all met. Remaining blockers before exit: T-005, T-006, T-007, T-008 (all @codex). T-001/T-002/T-003/T-010 exit inputs are now review-cleared.
- Open questions: none
- Next: @codex to take T-005..T-008 (and T-019); once those are Done + reviewed, @claude performs the T-009 Phase 0 exit review

## 2026-07-05 21:40 @claude — Review T-011..T-015
- Did: reviewed the six-commit batch (f8d6eb8..8d7f27b) against each task's AC and PLAN.md; moved T-011, T-012, T-013, T-014, T-015 to Done with Review: PASS
- Files: TASKS.md, WORKLOG.md
- Evidence: read lib/capture/template_engine/template_matcher.dart + field_normalizer.dart, test/capture/parser_cascade_test.dart, test/capture/template_engine/field_normalizer_test.dart, assets/seed/*.json + test/assets/seed_assets_test.dart, and the TASKS/README/WORKLOG diffs; independently verified seed referential integrity (every category_seed value resolves to a real categories.json id) and category taxonomy completeness (18/18, correct is_spending flags). Could not run `flutter test`/`analyze` — Flutter/Dart are not on PATH in this environment — so the review relies on reading source + tests plus @codex's logged green analyze/test and GitNexus impact(LOW)/detect_changes(clean) evidence, not a fresh run.
- Decisions: all five PASS. T-011 correctly catches FormatException + ArgumentError covering all four throw sites and rejects via Err(unparsed) per §7.1; T-012 UTC parseDate + timezone-stable test; T-013 seed data complete with a test asserting completeness and referential integrity; T-014 reconciled the board without self-approving @claude reviews and folded the openEncryptedDatabase wiring into T-006; T-015 README accurate. Non-blocking follow-ups recorded on T-011/T-012 (broad ArgumentError catch; fallback timezone still caller-supplied; numeric-but-out-of-range dates roll over instead of rejecting).
- Open questions: none blocking
- Next: T-001, T-002, T-010 remain PENDING @claude review; then T-005/T-006/T-007/T-008 before the T-009 Phase 0 exit review

## 2026-07-05 21:28 @codex — T-015
- Did: refreshed README Current Status to reflect working repo-local Flutter verification and the device-tested Android SQLCipher migration
- Files: README.md, TASKS.md, WORKLOG.md
- Evidence: `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk with README/task/worklog-only scope
- Decisions: kept status Phase 0/in-progress; did not claim @claude review pass or Phase 0 exit
- Open questions: none
- Next: @claude review T-011 through T-015; T-005/T-006/T-007/T-008 remain separate Phase 0 work

## 2026-07-05 21:22 @codex — T-014
- Did: reconciled TASKS.md state for T-001, T-002, and T-010 against WORKLOG evidence; kept all three in review for @claude; clarified T-010 provider/device-test scope and moved app-level database opener wiring into T-006
- Files: TASKS.md, WORKLOG.md
- Evidence: `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk with task/worklog-only scope
- Decisions: did not self-approve @claude review items; did not implement T-006 wiring, Kotlin unit tests, fixture runner, or CI guard follow-ups
- Open questions: none
- Next: T-015 README status refresh

## 2026-07-05 21:15 @codex — T-013
- Did: filled PLAN.md section 5 category seed assets, replaced empty merchant category seed map with a starter alias map, documented seed-growth expectations, and added JSON completeness tests
- Files: assets/seed/categories.json, assets/seed/category_seed.json, docs/seed-assets.md, test/assets/seed_assets_test.dart, TASKS.md, WORKLOG.md
- Evidence: `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk with seed/doc/test-only scope
- Decisions: kept `category_seed.json` as a direct merchant-to-category map for the future T-005 loader; documented the growth note in docs rather than adding metadata keys to the JSON map
- Open questions: none
- Next: T-014 board reconciliation

## 2026-07-05 21:08 @codex — T-012
- Did: changed parsed template dates to `DateTime.utc`; updated parseDate tests to assert UTC equality and timezone-stable epoch milliseconds
- Files: lib/capture/template_engine/field_normalizer.dart, test/capture/template_engine/field_normalizer_test.dart, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact LOW for `FieldNormalizer.parseDate` (2 direct callers, 2 affected processes, 4 impacted symbols); `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk with no affected processes
- Decisions: fallback timestamps remain caller-provided because fallback uses `sms.receivedAt`; only SMS-parsed dates are normalized to UTC
- Open questions: none
- Next: T-013 seed assets

## 2026-07-05 21:02 @codex — T-011
- Did: made matched-but-malformed templates expected misses at the TemplateMatcher boundary; added ParserCascade regressions for non-positive amount, garbage amount, non-numeric date, and invalid direction returning `Err(ParseFailure.unparsed)`
- Files: lib/capture/template_engine/template_matcher.dart, test/capture/parser_cascade_test.dart, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact LOW for `TemplateMatcher.match` (1 direct caller `ParserCascade.parse`, 1 affected process, 2 impacted symbols); `flutter analyze` clean; `flutter test` passed; `detect_changes` low risk with parser/test/doc scope
- Decisions: kept `FieldNormalizer` exceptions narrow and internal; `TemplateMatcher` catches only `FormatException`/`ArgumentError` and continues to later templates
- Open questions: none
- Next: T-012 UTC parsed dates

## 2026-07-05 20:58 @codex — Groom parser/data/process/doc follow-ups
- Did: groomed the five requested Phase 0 follow-ups as T-011 through T-015 before implementation; updated T-006 AC to fold AndroidKeystoreDatabasePassphraseProvider wiring into the provider task; proposed separate out-of-scope follow-ups T-016 through T-018 for Kotlin tests, fixture runner work, and CI generated-code guards
- Files: TASKS.md, WORKLOG.md
- Evidence: GitNexus impact preflight completed before parser symbol edits: `TemplateMatcher.match` LOW risk (1 direct caller, 1 affected process), `FieldNormalizer.parseDate` LOW risk (2 direct callers, 2 affected processes)
- Decisions: agreed with prompt scoping; did not start Phase 1 work; did not self-approve @claude review items
- Open questions: none
- Next: implement T-011 first

## 2026-07-05 21:05 @codex — T-010
- Did: added Android Keystore-backed SQLCipher passphrase provider, native MethodChannel storage, debug-only reset hook for integration tests, and wired the Android migration test to use the stored passphrase instead of a literal constant
- Files: lib/core/crypto/database_cipher.dart, android/app/src/main/kotlin/com/paisatrack/MainActivity.kt, test/core/crypto/database_cipher_test.dart, integration_test/encrypted_database_migration_test.dart, docs/schema.md, TASKS.md, WORKLOG.md
- Evidence: GitNexus impact was LOW for `openEncryptedDatabase` (2 direct test callers, 2 DB test flows), `DatabasePassphrase` (2 importing test files), and `MainActivity` (0 upstream dependents); `flutter test` passed; `flutter analyze --no-pub` clean; `flutter test integration_test/encrypted_database_migration_test.dart -d 192.168.1.10:5555` passed on motorola_edge_50_pro
- Decisions: implemented native Android Keystore AES-GCM wrapping rather than adding a secure-storage plugin; requested StrongBox when the device reports support and falls back to normal Keystore if StrongBox key generation fails; test reset is gated to debug builds via `ApplicationInfo.FLAG_DEBUGGABLE`
- Open questions: none
- Next: Claude review of T-010; Codex can continue with T-005 after review or proceed if @human wants parallel Phase 0 progress

## 2026-07-05 20:24 @claude — Review T-003, T-004
- Did: reviewed T-003 (Drift schema v1 + migration test) and T-004 (Phase 0 task grooming) against the COLLABORATION.md §4 checklist
- Files: TASKS.md, WORKLOG.md
- Evidence: read lib/data/db/database.dart + lib/data/db/tables/*.dart, lib/core/crypto/database_cipher.dart, test/data/db/app_database_migration_test.dart, integration_test/encrypted_database_migration_test.dart, and docs/schema.md against PLAN.md §6.1/§6.2/§8; checked Ready section (T-005–T-009) AC quality and dependency ordering. Could not re-run `flutter test`/`flutter analyze` in this sandbox — the repo-local Flutter binary is built for a different architecture (`Exec format error`) — so the review relies on reading test source directly plus the CI/device evidence already logged by @codex, not a fresh run.
- Decisions: T-003 → Review: PASS (schema matches plan exactly for tables in scope; tests are non-vacuous — assert real table/index names, schema version, and a live `cipher_version` check with fail-closed behavior; docs updated). T-004 → Review: PASS (Ready tasks are small, testable, correctly ordered/dependent). Both moved to Done. Noted but not blocking: PLAN.md §8 requires the SQLCipher passphrase to be generated on first run and stored in Android Keystore; the current opener takes a plain passphrase constant with no Keystore-backed provider task in Ready — filed T-010 to close that gap.
- Open questions: none blocking further Phase 0 work
- Next: @codex can pick up T-005 (or T-010 first, since Phase 0's "encrypted DB" exit criterion implies a real device-derived key, not a test constant)

## 2026-07-05 19:20 @codex — Project rule: tests + docs
- Did: added a documented Definition of Done requiring tests, code documentation, and project documentation for every feature; added Dart `///` comments to current public app, parser, model, schema, and database helper surfaces
- Files: README.md, COLLABORATION.md, docs/development.md, lib/app.dart, lib/main.dart, lib/core/*, lib/capture/*, lib/data/models/*, lib/data/db/database.dart, lib/data/db/tables/*, WORKLOG.md
- Evidence: `dart format lib` completed; `flutter analyze` clean
- Decisions: made COLLABORATION.md the enforceable workflow location and docs/development.md the detailed guidance; kept generated `database.g.dart` untouched
- Next: future feature tasks must include test evidence, code documentation, and project documentation updates, or explicitly record why not

## 2026-07-05 19:10 @codex — T-004
- Did: groomed remaining Phase 0 work into ordered Ready tasks T-005 through T-009 after @human asked Codex to proceed despite T-004 being proposed for @claude
- Files: TASKS.md, WORKLOG.md
- Evidence: Ready contains small AC-backed tasks for DB seed loading, Riverpod database provider skeleton, parser fixture harness, CI guardrails, and Phase 0 exit review
- Decisions: kept T-001/T-002/T-003 in review; made new implementation tasks depend on review pass where they build on unreviewed work
- Next: after review pass, Codex should take T-005; Claude should still review T-004 and perform T-009 exit review

## 2026-07-05 18:55 @codex — T-003
- Did: added Drift schema version 1 for transactions, raw_sms, merchants, merchant_aliases, categories, rules, and feedback; added SQLCipher opener that fails closed when cipher support is unavailable; added host migration test plus Android integration migration test
- Files: pubspec.yaml, pubspec.lock, docs/schema.md, lib/core/crypto/database_cipher.dart, lib/data/db/*, test/data/db/app_database_migration_test.dart, integration_test/encrypted_database_migration_test.dart, TASKS.md
- Evidence: `flutter test integration_test/encrypted_database_migration_test.dart -d 192.168.1.10:5555` passed on motorola_edge_50_pro over wireless ADB; `flutter test` passed with host SQLCipher test skipped; `flutter analyze` clean
- Decisions: pinned Drift/Drift Dev to 2.18.0 and sqlite3 to ^2.4.0 so Android SQLCipher override API is available; host VM test skips when SQLCipher is not linked, while device integration test is the encrypted acceptance check
- Next: Claude review of T-003; seed loading/repository wrappers can be groomed as follow-up tasks

## 2026-07-05 18:25 @codex — T-001/T-002
- Did: created GitHub repo and pushed initial scaffold; installed repo-local Flutter 3.44.4; generated Android platform files with `flutter create`; normalized Android package to `com.paisatrack`; configured Flutter to use JDK 17; verified Android SDK 36 + licenses; added README setup notes
- Files: README.md, TASKS.md, WORKLOG.md, .gitignore, .metadata, android/*, paisatrack.iml, pubspec.lock, test/widget_test.dart
- Evidence: `flutter doctor -v` Android toolchain green; `flutter test` 5/5; `flutter analyze` clean; `flutter build apk --debug` produced `build/app/outputs/flutter-apk/app-debug.apk`
- Decisions: keep `.tooling/flutter` ignored but document it; leave non-Android doctor warnings (Xcode, Chrome, PATH) as non-blocking for Android-first Phase 0
- Open questions: `.skills/` appeared untracked with project process guidance; not committed in this task pending owner confirmation
- Next: Claude review of T-001/T-002, then T-003 drift schema v1 + migration test

## 2026-07-05 17:30 @codex — T-001
- Did: initialized git repo; added PLAN.md and COLLABORATION.md from supplied attachments; created task board, worklog, docs stubs, CI, core Dart contracts, parser cascade stub, fixture harness tests, and Android SMS filter placeholder
- Files: README.md, PLAN.md, COLLABORATION.md, TASKS.md, WORKLOG.md, docs/*, lib/*, test/*, assets/*, android/*
- Evidence: `git init` succeeded after approval; `flutter --version` and `dart --version` unavailable in this environment
- Decisions: kept Phase 0 scaffold dependency-light; parser cascade returns unparsed until templates are added
- Open questions: install/provide Flutter SDK so T-001/T-002 can be verified with `flutter test`
- Next: after Flutter is available, run `flutter create .` carefully and normalize generated project files
