## 2026-07-09 @claude — PHASE P2 EXIT REVIEW (T-046)

Verdict: **PASS by code evidence on all four PLAN §9 Phase 2 exit criteria**, conditional on three on-device sign-offs and the commit unblock listed below. Reviewed T-035..T-045 against the criteria; no criterion is unmet in code.

Criterion 1 — "You use it daily." The full daily loop exists end to end: live SMS capture + 3-month backfill (Phase 1), categorizer ladder (T-039), decision-policy status (T-040), manual entry (T-037), detail/edit-with-feedback (T-038), category manager (T-041), ask-now notifications (T-044), weekly review (T-045), settings + theme + reset (T-042), encrypted backup (T-043). Nothing functional is missing for daily use. Final sign-off is inherently human — a real day of use — so this stays conditional on your confirmation, not on code.

Criterion 2 — "≤2 asks/day." Enforced by construction. `DecisionPolicy` only asks in the 0.6–0.9 confidence band behind the amount/merchant-count gates, and `SmsIngestor._maybeAsk` caps asks by `_countAskedToday` against `askDailyBudget` — now read from the Settings slider (default 2) via `smsCaptureBootstrapProvider`, so the ingest gate and the notifier share one budget (T-044). The T-040 fix keeps suppressed duplicate echoes off the budget (`is_deleted=0 AND duplicate_of_txn_id IS NULL`). Covered by `decision_policy_test.dart` (budget-exhaustion branch) and `sms_ingestion_test.dart`. PASS; recommend confirming the count holds over one real day on device.

Criterion 3 — "A correction on a P2P transfer creates a visible rule and the next identical transfer auto-labels." Traced end to end. Correcting a P2P transfer runs `TransactionRepository.correctWithRule`; `_ruleInputFor` sees the row's `counterparty_vpa` and inserts a `counterparty`-type rule keyed on that VPA (visible in the rules table / category manager), inside the same transaction as the feedback row and the status→`confirmed` update. On the next identical transfer, `Categorizer` calls `RuleRepository.findMatch`, which checks `counterparty` (exact VPA) before `merchant`, returns the rule at confidence 1.0 / source `rule`; `DecisionPolicy` treats rule-backed (≥0.97) as `auto`, so the transfer auto-labels with no ask. This is exactly the criterion. PASS by code trace; capture a device/integration demo as the canonical artifact.

Criterion 4 — "export→wipe→import round-trips losslessly." T-043 encrypts domain rows with Argon2id + AES-256-GCM; `encrypted_backup_service_test.dart` asserts a byte-equivalent domain round-trip with no plaintext file and wrong-passphrase fail-closed. PASS (tests human-verified in the T-043 toolchain pass); capture one on-device round-trip for the exit artifact.

Blockers / conditions before Phase 3 grooming:
1. **Commit is blocked.** A stale `.git/index.lock` (0 bytes, no git process holding it) can't be unlinked from the sandbox ("Operation not permitted" on the mount). The T-044/T-045 doc updates and this review are written but uncommitted until you run `rm .git/index.lock` on the Mac.
2. **Canonical toolchain run owed.** A full `flutter test --no-pub --concurrency=1` over T-044/T-045 must run on the device toolchain (the repo-local Flutter SDK is wrong-arch for this Linux sandbox); fold in T-047's deferred on-device export re-run for the canonical coverage number at the same time.
3. **On-device evidence capture** for criteria 1, 3, and 4 — daily-use confirmation, the P2P auto-label demo, and one export→wipe→import round-trip. Code PASSES all three; these are the "prove it on device" sign-offs, not open defects.
4. **Refresh the GitNexus index** (`gitnexus analyze`) — the baseline (1f751b5) predates the T-044/T-045 code commit (1ba1e82), so Phase 3 impact/detect_changes preflights need a re-analysis to be accurate.

Carry-forward into Phase 3 (non-blocking): DecisionPolicy v2 adaptive per-category thresholds supersede the static v1; the parser-confidence-as-merchant-confidence proxy is replaced by the embedder; a per-enricher confidence trail feeds the model-metrics dev screen.

## 2026-07-09 @claude — T-044 ask-now notifications + T-045 weekly review (Done)

- Built and committed (1ba1e82) the two interruption surfaces that close out Phase 2's build queue.
- T-044 ask-now: `AskNowPayloadBuilder` builds top-3-guess notifications (best guess first); `MethodChannel('com.paisatrack/ask_now')` gateway (`show` / `takePendingResponses`); `AskNowResponseHandler` drains queued answers into `TransactionRepository.correctWithRule(context: 'ask_now')`. `askNowNotificationControllerProvider` (watched in `app.dart`) shows `askQueueProvider` (`status='asked'`) rows and drains pending responses on every build — i.e. on app start.
- App-killed correctness: `AskNowNotificationReceiver.kt` handles action-button taps + RemoteInput free-text and persists responses to SharedPreferences; the Dart side drains them on next launch and acks handled ids so answers are applied once and never double-applied.
- Review-hook fix 1 (queue drain, patched into `ask_now_notifications.dart`): `AskNowResponseHandler.handle` now acks **every processed response**, not only successfully-corrected ones. A response that resolves to null (unmatched free text with no fallback) or whose transaction is gone (`correctWithRule` throws `StateError`) is caught and still ack'd, so it drains instead of re-firing on every app start; the return value still reports only genuinely-applied corrections. Prevents a poison-pill row from wedging the queue.
- Review-hook fix 2 (disposed-ref race in `askNowNotificationControllerProvider`): the controller watches `shownAskNowTxnIdsProvider` and also writes it after showing. Previously each queued ask was shown concurrently with a per-show `.then` callback that updated that provider; on a multi-item queue the first callback disposed this controller instance mid-flight, so the other in-flight callbacks hit a disposed `ref` (uncaught `StateError`) and their items got re-shown by the rebuilt instance. Fix: a `disposed` flag via `ref.onDispose`, shows run **sequentially** collecting successes locally, and the "shown" set is committed in **one guarded write after all shows finish** — no mid-flight self-dispose. Also guarded the response-poller's post-await write with the same flag. Regression test added (`controller shows each queued ask once on a multi-item queue without disposed-ref errors`) driving the controller through a `ProviderContainer` with a two-item queue.
- One-write principle (PLAN §1 #3): `correctWithRule` does rule insert + feedback row(s) + txn update→`confirmed` inside a single `_database.transaction`. Free-text answers resolve by case-insensitive category-name match, else land `Other` with the text kept as the description.
- Ask-budget now reads the Settings slider: `smsCaptureBootstrapProvider` threads `settings.askDailyBudget` (fallback `AppConstants.askNowDailyBudget`) into `SmsIngestor._askDailyBudget` — closes the non-blocking note from the T-040 review (was reading `AppConstants` directly). `POST_NOTIFICATIONS` added for Android 13+.
- Income-side bug (@human caught): credits were being offered spending categories (Food/Groceries). Fixed in the builder — when `direction == credit` it drops any `isSpending` category except `Other`, so credit actions surface `Other`/`Transfers`/`Income`. Regression test added (`payload builder uses income-side categories for credits`).
- T-045 weekly review: new **Review** tab in `HomeShell` fed by `reviewQueueProvider` → `watchReviewQueue()` (`status='needs_review'`, not deleted, not a duplicate, newest first). Swipe-to-confirm → `confirm()` (status→`confirmed`, category untouched); tap-to-correct → correction sheet → `correctWithRule(context: 'batch_review')`. Empty state "All caught up" per design-system §5.
- Verification: `flutter analyze --no-pub` clean; targeted Flutter tests (notifications + review) green; Android JVM tests green; `dart format` clean. Test runs are **human-verified** — the repo-local Flutter SDK is wrong-arch for this Linux sandbox (same constraint documented in prior @claude sessions), so I did not re-execute them here. GitNexus `detect_changes`: MEDIUM, expected ingest/notification surface (no unexpected symbols). Full-suite `flutter test` re-run folds into T-046 exit evidence.
- Next: T-046 Phase 2 exit review — verify PLAN §9 exit criteria against T-035..T-045 evidence, then Phase 3 grooming.

## 2026-07-08 @claude — Review T-040 wiring (PASS with two fixes)

- Reviewed @codex's `DecisionPolicy` → `SmsIngestor` wiring against PLAN §7.5 and the T-040 AC. Semantics verified: min(parser, category) confidence drives the ladder; rule-backed (min 0.97) → auto; seed (0.8) → ask when amount/merchant-count eligible and budget remains, else needs_review; fallback (0.3) → needs_review; unseen-P2P asks before the confidence gate (AC's "always asks once"), degrading to needs_review when the budget is spent; manual entries and the detail-edit path untouched (status 'confirmed' flows preserved).
- Fix 1 (AC deviation): `input.amount >= 500 || merchantTxnCount >= 3` hardcoded the thresholds the AC requires from `constants.dart` — added `AppConstants.askAmountThreshold` (500.0) + `askMerchantTxnCount` (3) and referenced them in the policy. Impact preflight LOW.
- Fix 2 (real budget leak): the policy also ran for suppressed duplicate echoes, so a hidden echo (bank+wallet pair) could land `status='asked'` — consuming one of the 2 daily asks on a row that never surfaces — and `_countAskedToday` counted such rows. Echoes now always land `'auto'` (pre-T-040 behavior for hidden rows) and the budget count filters `is_deleted=0 AND duplicate_of_txn_id IS NULL`.
- Both fixes are behavior-preserving for every existing test scenario (no test tickles an echo+ask interaction); suite re-run required before T-040 → Done.
- Closure: suite re-run green over both fixes — analyze clean, 101 passed / 2 known host skips. T-040 → Done; T-044 + T-045 unblocked (the last build tasks before the T-046 Phase 2 exit review).

## 2026-07-08 @claude — TOOLCHAIN VERIFICATION PASS (T-037/38/39, T-041/42/43, T-047)

- Result: **full suite green — `flutter analyze --no-pub` clean; `flutter test --no-pub --concurrency=1` 96 passed / 2 known host skips** (scratch dashboard debug test; host SQLCipher migration skip). First complete toolchain run over the whole Phase 2 chain. T-037/38/39 and T-047 → Done; T-041/42/43 verification lines added; T-040 wiring unblocked.
- CRITICAL regression found & fixed (T-039): `seedDefaultCategories()` was defined but never called in production. With `PRAGMA foreign_keys = ON`, the categorizer stamps `category_id` on every parsed record; the FK against the empty categories table failed and the WHOLE ingest transaction — including the raw_sms insert — rolled back, silently swallowed by `_ingestSafely`. On device, SMS capture would have stopped entirely the moment T-039 shipped. Fix: `appDatabaseProvider` seeds after open (idempotent insertOrIgnore, user edits preserved); capture/enrichment test setups seed likewise. The detect_changes CRITICAL flag on this change set was accurate, not noise.
- Test-infrastructure findings fixed along the way (commit 73abbab + follow-ups):
  - Widget tests driving REAL drift streams raced the first emission under testWidgets' FakeAsync; fixed with bounded runAsync/pump alternation (real event-loop slices deliver completions; fake pumps run the microtasks they queue). A stuck stream also wedged `database.close()` in tearDown — the "suite hangs after failure" symptom.
  - Real file IO started under FakeAsync deadlocks if awaited inside a single runAsync (its continuations queue as fake-zone microtasks that only flush after runAsync returns) — root cause of the settings widget-test hang; same alternation pattern fixes it.
  - Lazy ListView: detail-screen fields below the 600x800 test viewport are never built; assertions now scroll each into view (`scrollUntilVisible`), with layout-order-aware assert ordering.
  - One analyze info fixed (const literal, dev unparsed screen); stray `zz_probe_test.dart` scratch file removed.
- Known-noise note: the drift "AppDatabase created multiple times" warning during the settings reset test is intentional (the reset service reopens the DB) — not a defect.
- T-047 closure evidence: fixture runner + per-bank coverage suites green over `indusind_neft_credit_v1`/`indusind_ach_credit_v1` — all 13 new positives parse field-exact, all 4 negatives stay unparsed. Statement-side 99.03% stands as simulation evidence; canonical on-device export re-run folds into T-046 exit evidence.
- Next: T-040 wiring (@codex, now unblocked) → T-044 + T-045 → T-046 Phase 2 exit review (@claude).

## 2026-07-08 @codex — T-040 wiring Decision policy into ingest

- Did: wired `DecisionPolicy` into `SmsIngestor` so parsed SMS transactions now
  land with `auto`, `asked`, or `needs_review` instead of always `auto`.
  Runtime inputs come from parser confidence, T-039 category confidence, prior
  same merchant/VPA rows, same-VPA seen history, and today's existing `asked`
  count against `AppConstants.askNowDailyBudget`.
- Tests: extended `sms_ingestion_test` for seed low-risk review, high-amount
  ask, budget exhaustion, familiar merchant ask, rule-backed auto, and unseen
  P2P ask-once. Existing `decision_policy_test` still covers isolated branch
  behavior.
- Evidence: pre-edit GitNexus impact LOW for `SmsIngestor`,
  `_transactionCompanionFor`, `SmsIngestor.ingest`, `smsCaptureBootstrapProvider`,
  `smsBackfillProvider`, and `DecisionPolicy`; affected processes are the
  expected live/backfill ingest flows. `flutter analyze --no-pub` passed.
  Targeted decision/ingestion tests passed. Backfill tests passed. Full
  `flutter test --no-pub --concurrency=1` passed: 101 passed / 2 known host
  skips.
- Follow-up fix: local full-suite rerun exposed that the P2P ask-once test was
  accidentally creating a duplicate echo (same VPA/amount/time window), which
  correctly stays `auto` because it is suppressed and hidden. The regression
  test now uses two payments outside the duplicate window, and the policy
  explicitly keeps seen P2P counterparties in `needs_review`. Analyzer and full
  suite are green after the fix.
- Decisions: kept ask-budget source at `AppConstants.askNowDailyBudget` for
  this task, matching T-040 AC. The Settings slider can be connected later
  through a shared settings boundary without introducing a capture-to-feature
  dependency.
- Open questions: none.

## 2026-07-08 @codex — Docs status refresh

- Did: refreshed README, PROJECT_STATUS_REPORT, docs/architecture, and the
  TASKS header/comment so the docs consistently describe current Phase 2 state
  instead of the older Phase 0 / pre-T-047 snapshot.
- Details: README now calls Phase 2 "in progress", lists the current focus
  (verification, T-040 wiring, T-044, T-045, T-046), and records T-047's
  99.03% fixture/SMS-dump coverage with its remaining verification caveat.
  PROJECT_STATUS_REPORT was rewritten as a current 2026-07-08 status brief.
  Architecture now notes DecisionPolicy is not wired yet and distinguishes the
  Phase 1 94.4% device evidence from T-047's 99.03% simulation evidence.
- Evidence: docs-only change; no Flutter tests run.
- Open questions: none.

## 2026-07-08 @codex — T-040 prep Decision policy v1

- Did: added isolated `DecisionPolicy` with status outputs only. No
  `SmsIngestor`, capture, categorizer, notification, or transaction write-path
  wiring was added.
- Behavior: uses `AppConstants.silentConfidenceThreshold`,
  `askConfidenceThreshold`, and `askNowDailyBudget`; `min(merchant.c,
  category.c)` controls normal decisions; medium-confidence asks require amount
  >= 500 or merchant txn count >= 3 and budget left; unseen P2P counterparties
  ask once when budget remains.
- Tests/docs: wrote table-driven policy tests for every branch and wire names;
  updated architecture docs to note wiring is deferred until T-039 clears.
  Per @human instruction, tests were not executed.
- Evidence: pre-edit impact on `AppConstants` MEDIUM, no affected processes.

## 2026-07-08 @codex — T-041 Category manager

- Did: added Settings -> Manage categories screen. Users can add, rename, and
  merge categories. User-created categories use `is_user_created=true`; unknown
  icon/color values continue through `CategoryVisuals` fallback behavior.
- Repository: `CategoryRepository.addUserCategory`, `renameCategory`, and
  `mergeCategory`. Merge runs in one Drift transaction, updates transactions,
  rules, and child category parent links from source to target, then deletes the
  source category.
- Tests/docs: wrote repository test for add/rename/merge retro-apply to
  transactions and rules; updated development manual check. Per @human
  instruction, tests were not executed.
- Evidence: pre-edit impact after refreshed index: `CategoryRepository` LOW,
  `CategoryVisuals` LOW, `SettingsScreen` LOW.

## 2026-07-08 @codex — T-043 Encrypted export/import

- Did: added encrypted backup service and Settings actions for export/import.
  Exports write app-private `paisatrack_export.ptrack`; import reads the same
  file. Plaintext domain JSON is held in memory only.
- Crypto: added free/open-source `cryptography` dependency. Archive encryption
  uses Argon2id (19 MiB, parallelism 1, iterations 2, 32-byte key) and
  AES-256-GCM with stored salt/nonce/MAC/ciphertext.
- Data: archive version 1 serializes categories, merchants, raw SMS, merchant
  aliases, transactions, rules, and feedback. Import validates the archive,
  decrypts fail-closed on wrong passphrase/corruption, and replaces domain rows
  transactionally.
- Tests/docs: wrote backup tests for encrypted round-trip and wrong-passphrase
  fail-closed behavior; updated privacy/schema/development docs. Per @human
  instruction after T-042, tests were not executed.
- Evidence: refreshed GitNexus after T-042. Pre-edit impact: `SettingsScreen`
  LOW, `AppDataResetService` LOW, `AppDatabase` CRITICAL (expected whole-domain
  backup/restore surface).

## 2026-07-08 @codex — T-042 Settings v1

- Did: added Settings as a fourth HomeShell destination with theme choice
  (dark/light/system), ask-budget control, read-only feature-flag display, and
  Delete everything confirmation. `PaisaTrackApp` now reads persisted theme
  mode from `appSettingsControllerProvider`; app settings live in app-private
  `settings.json`.
- Data reset: added `AppDataResetService`, exported `appDatabaseFileName`,
  seeded bundled categories on DB open, and added production
  `clearPassphrase` on `com.paisatrack/database_passphrase` so Settings can
  delete SQLCipher sidecars and rotate the Android Keystore-wrapped DB key.
- Docs/tests: updated `docs/architecture.md`, `docs/privacy.md`, and
  `docs/development.md`. Tests were written for settings persistence, settings
  UI controls, reset proof, and passphrase clear channel.
- Evidence: refreshed GitNexus index successfully after sandbox approval.
  Pre-edit impact: `PaisaTrackApp` LOW, `HomeShell` LOW,
  `databasePassphraseProvider` LOW, `appDatabaseProvider` LOW,
  `AndroidKeystoreDatabasePassphraseProvider` MEDIUM, `DatabasePassphraseStore`
  LOW, `configureFlutterEngine` LOW, `AppConstants` MEDIUM. No HIGH/CRITICAL
  surprise. Test execution caveat: targeted Flutter tests were started, then
  interrupted/hung in the Settings widget test; @human instructed "skip the
  test execution, finish rest", so no test result is claimed.
- Post-commit review found and fixed before continuing: restored SQLCipher
  `isolateSetup` so Android loads SQLCipher before the background connection
  opens, and moved `appDatabaseProvider` invalidation until after database
  files/key/settings are cleared so active listeners cannot reopen with the old
  key mid-reset. Second review pass found and fixed two more reset edge cases:
  reset no longer requires a successful database open before deleting files/key,
  and provider database close is tolerant of reset-triggered early close.

## 2026-07-08 @claude — T-047 templates + coverage re-run (99.03%)

- Did: added two credit templates to `assets/templates/indusind.json` — `indusind_neft_credit_v1` (`Your IndusInd Account X+{account} has been credited for INR {amount} towards N/{ref}/{ifsc}/{merchant} . Call`; merchant = remitter segment for seed categorization, ref = bare NEFT token for statement containment, no balance, ts falls back to receive time) and `indusind_ach_credit_v1` (exact mirror of `indusind_ach_debit_v1`: `Credited; INR {amount} Ref-{ref}.Bal INR {balance}`, full `ACH CR INW PAY/...` ref). Both use only field_normalizer's known groups (amount/account/merchant/vpa/balance/ref/date).
- Validation without a Dart toolchain: regexes checked in Python against every fixture — all 13 new positives produce field-exact expected.json values (amount, xx-account hint, ref, merchant, balance); the 4 negatives and all 44 pre-existing indusind fixture bodies match neither new template. Caught one engine subtlety: `template_registry` compiles `caseSensitive: false`, so validation and the coverage simulation use case-insensitive matching (the real `A/C` vs template `A/c` variance is why).
- docs/sms-templates.md: both new templates documented + two known gaps (IMPS/P2A: 3 occurrences ever, negative-fixtured per the ≥5 law; quarterly interest: no SMS since 2023, legacy shape pinned; plus the VARUN 2026-04-21 no-SMS dividend observation).
- Coverage re-run (AC): full SMS dump (4,100 parsed records — same source of truth as the device DB) through all 8 templates, standard matching ladder vs statement. Window 2026-04-06..2026-07-06: **407/411 = 99.03% covered** (from 94.4%; >97% criterion PASS). The 4 uncovered are exactly the documented gaps: VARUN dividend (no SMS), IMPS ×2 (SMS exist, deliberately untemplated), interest (no SMS). Appended to BankStatement/coverage_report.md; fixture-mode reconcile also verifies all 13 positives pin their statement rows by ref (BankStatement/fixture_recon_t047.md). Note: earlier "21 of 23 recover" projection was off by 2 — IMPS rows stay uncovered by design; actual recovery 19 of 23.
- detect_changes(scope: all) over the working tree: 4 files / 9 symbols / 0 affected execution flows, risk LOW — templates+fixtures+docs are data, no code paths touched.
- Remaining for T-047 Done: `flutter test` (fixture runner + `sms_bank_fixture_coverage_test` must go green with the new templates — no toolchain in this sandbox) and a canonical device re-export coverage run; both fold into the same @codex verification pass as T-037/38/39.

## 2026-07-08 @claude — T-047 fixtures pulled (SMS dump via adb from @human)

- Did: @human dumped IndusInd-sender SMS via `adb shell content query --uri content://sms/inbox` → `BankStatement/indusb_sms_dump.txt` (gitignored; 4,698 raw rows). Matched bodies against the 23 uncovered Transfer Credit statement rows and committed 17 fixtures to `test/fixtures/sms/indusind/`:
  - `indusb_neft_01..06` (positive): "Your IndusInd Account XXXXXXXX…has been credited for INR…towards N/<ref>/<IFSC>/<remitter>" — SAL salary, ICICI PRU / GR0WW (AXIS) / MOTILAL (CMS ref) / QUANT redemptions, ₹1 IDFB penny-drop. Covers integer ("INR 1", "INR 161652") and decimal ("INR 39207.42") amount forms. Expected: channel netbanking, merchant_raw = remitter segment (feeds seed categorization, e.g. SAL), ref_id = bare ref token (statement-desc containment for reconciliation), no balance in shape, conf 0.97.
  - `indusb_achcr_01..07` (positive): "IndusInd A/C **…Credited; INR…Ref-ACH CR INW PAY/<ref>/<remitter>.Bal INR…" — every dividend row that produced an SMS. Expected mirrors existing `indusb_ach_*` (ACH DR) convention: merchant_raw null, full ref string, balance_after set, netbanking, 0.97.
  - `indusb_imps_p2a_gap_01..03` (negative, expected err:unparsed): IMPS/P2A credit shape has only 3 occurrences in the entire SMS history (2× 2026-06-09, 1× 2026-03-30) — below the ≥5 fixture-first bar, so committed as known-gap negatives per T-047 AC.
  - `indusb_interest_legacy_gap_01` (negative): quarterly SB interest generates NO SMS since 2023 — the fixture pins the last-seen 2023 legacy shape ("…credited…towards Interest Credit for the quarter ending June…") as err:unparsed. The 2026-06-30 `Int.Pd` statement row is statement-only. Second documented gap: the 2026-04-21 VARUN ₹5.50 dividend produced no SMS either (7 of 8 ACH-CR rows did).
- Sanitization: account masks → 4521-forms in all variants (`XXXXXXXX4521`, `**4521`, `100***234521`), IMPS remitter account re-masked; refs/amounts/balances/senders/timestamps kept real per existing fixture convention (reconciliation matches by ref containment). Leak-checked: no `6265` in any committed body. All 61 indusind expected.json parse; .txt/.expected.json pairing intact.
- Note for @codex: the 13 positives intentionally have NO matching template yet — they encode the target for T-047's template work and will fail the fixture runner until `assets/templates/indusind.json` gains neft/achcr credit templates. After templates: document both known gaps in docs/sms-templates.md and re-run the coverage script — 21 of 23 uncovered rows should recover (expect ~99%; interest + VARUN 04-21 stay statement-only).
- Access note: pulled via one @human-run adb command; the sandbox cannot reach LAN devices (proxy 403s CONNECT to private ranges), so direct wireless-adb from here was not possible.

## 2026-07-08 @claude — Toolchain verification pass (T-037/T-038/T-039, partial) + T-047 fixture prep

- Did (GitNexus — first time runnable in a @claude sandbox): global npm install of gitnexus dies at sandbox timeouts (native tree-sitter builds), so installed locally with `--ignore-scripts`, repaired `@ladybugdb/core` from its bundled linux-arm64 prebuilt (`node install.js`), and compiled tree-sitter core + all 10 grammar bindings by hand — nodejs.org is blocked so node-gyp got headers from the system package via `--nodedir` pointing at `/usr/include/node`. Registered the repo's existing `.gitnexus/` index with `gitnexus index .`.
- detect_changes(scope: compare, base_ref: b57aed4 = T-036, the last verified commit): **18 files, 30 symbols, 18 affected execution flows, risk CRITICAL.** All affected flows are ingest-cluster (`Run`/`_ingestSafely` → parser/dedup/normalization steps) — consistent with T-039 wiring the categorizer into `SmsIngestor`; no unexpected flow families. `git diff --stat b57aed4..HEAD` footprint matches the T-037/38/39 file lists in TASKS.md exactly (18 files; only expected lib/, test/, docs/, board files). detect_changes(scope: all): working tree clean (the three tasks are already committed), nothing to map.
- CRITICAL-risk note (CLAUDE.md requires surfacing): the rating reflects that the SMS ingest path — the app's core flow — was modified. That modification is precisely T-039's AC. Flagged to the human on 2026-07-08; proceeding was explicitly the point of the verification.
- Index caveat: `.gitnexus/` index still dates from 972a046 (pre-T-036), so symbols added by T-036..T-039 map at file granularity, and full `analyze` was NOT re-run here (sandbox 45s exec cap vs. documented KuzuDB corruption risk on interrupted analyze). Re-run `node .gitnexus/run.cjs analyze` on an unconstrained machine.
- Flutter analyze/test: still NOT runnable in this sandbox — aarch64 Linux, no Dart/Flutter SDK, and storage.googleapis.com / pub.dev / dl.google.com all blocked. `flutter analyze --no-pub` + `flutter test --no-pub --concurrency=1` remain with @codex. Ran the static checks that are possible without a toolchain: every JSON under assets/ and test/fixtures/sms/ parses; every fixture `.txt` has a paired `.expected.json` (and vice versa) across all bank dirs.
- T-047 prep: re-derived the 23 uncovered Transfer Credit statement rows (script logic replicated against BankStatement/*.xlsx + export.json; matches coverage_report.md exactly) and wrote the @human pull checklist to `BankStatement/t047_fixture_pull_checklist.md` (gitignored — contains row-level bank data): 12 NEFT (≥5 available ✅, incl. 3 SAL and a ₹1 penny-drop), 8 ACH-CR dividends (≥5 available ✅), 2 IMPS/P2A (<5 ⇒ negative known-gap fixtures), 1 quarterly interest (likely generates no SMS; document per AC). Suggested case names + sanitization rules included; existing `indusb_ach_*` are ACH **DR**, so new credits use an `achcr` prefix.
- Next: @codex (or any machine with Flutter) runs analyze + full test suite to move T-037/38/39 out of In Review; @human pulls the T-047 SMS bodies from the dev Unparsed screen using the checklist; then @codex adds templates and re-runs the coverage script (expect >97%).

## 2026-07-07 @claude — T-039

- Did: categorizer ladder (PLAN §7.4 steps 1+3) wired into ingest. New `lib/enrichment/`: `SeedCategoryMap` (case-insensitive, longest-key-first substring matcher over the bundled `assets/seed/category_seed.json`), `Categorizer` (rules → seed@0.8 → other@0.3; result carries categoryId/confidence/source/ruleId), `seedCategoryMapProvider` + `categorizerProvider`. New `RuleRepository` (lib/data/repositories/rule_repository.dart): `findMatch` honors match_types 'counterparty' (exact normalized VPA, checked before merchant since exact identity is the stronger signal) and 'merchant' (normalized substring); unknown match_types never match; rules with null `set_category_id` are skipped by the categorizer; `incrementHitCount` (SQL `hit_count = hit_count + 1`, no read-modify-write race) and `insert` (for the future correction flows). `SmsIngestor` gains an optional `Categorizer` (nullable so capture-only tests run without one; both production call sites — `smsCaptureBootstrapProvider`, `smsBackfillProvider` — supply it): parsed records land with `category_id` set, `confidence_json` gains `category: {c, src, rule_id?}`, and an applied rule's hit count increments inside the same ingest DB transaction.
- Also: fixed a confidence_json shape inconsistency introduced by T-037/T-038 — `insertManual` and `_parseConfidenceOf` used `{parse:{source,confidence}}` while `SmsIngestor` writes `{parser:{c,src}}`; both now use the ingestion shape (tests updated). docs/architecture.md gains an "Enrichment (Phase 2, in progress)" section.
- Files: lib/enrichment/categorizer.dart (new), lib/enrichment/seed_category_map.dart (new), lib/data/repositories/rule_repository.dart (new), lib/capture/sms_ingestion.dart, lib/capture/sms_backfill.dart, lib/data/repositories/transaction_repository.dart, docs/architecture.md, test/enrichment/categorizer_test.dart (new), test/capture/sms_ingestion_test.dart (helper awaits categorizerProvider; live-ingest test asserts seed categorization), test/features/transactions/manual_entry_screen_test.dart, test/features/transactions/transaction_detail_screen_test.dart, TASKS.md, WORKLOG.md.
- Evidence caveat: same as T-037/T-038 — no runnable Flutter or GitNexus here; analyze/test/impact/detect_changes deferred to @codex verification. Note for the verifier: the capture ingest write path changed again (categoryId + confidence_json shape), so the fixture-coverage and backfill suites are the ones to watch.
- Decisions: kept the categorizer OUT of `TransactionRepository.insertManual` — the user picks the category explicitly in the manual form, and PLAN's ladder is for parsed records; suppressed echoes still get categorized (harmless, keeps the write path uniform, and an un-suppress won't need re-enrichment); seed matching tries merchantRaw before counterpartyVpa so explicit merchant text wins over VPA heuristics.
- Open questions: whether merchant rules should be exact-match rather than substring once the ask flow starts generating them automatically (T-044) — substring matches PLAN's "merchant" teaching intent for now.
- Next: T-040 (decision policy) depends on T-039 and should wait for the verification pass; T-041/T-042/T-043 remain available.

## 2026-07-07 @claude — T-038

- Did: transaction detail + edit-with-feedback. List rows now push `TransactionDetailScreen` (all frozen §6.2 fields + status, null → '—'; amount header in semantic direction color with tabular figures; "Confidence trail" placeholder card showing parse source + confidence decoded from `confidence_json` with a Phase 3 note). Category dropdown and description field are editable and seeded once from the loaded row (stream re-emissions don't clobber in-progress edits); the category dropdown only renders once categories load and guards against ids not in the table (avoids the dropdown value assertion). Save calls new `TransactionRepository.updateWithFeedback(txnId, {categoryId, description, context='detail_edit', clock, feedbackIdFactory})`: inside one drift `transaction()` it reads the row, skips fields whose new value equals stored, writes the update (bumping `updated_at`), and inserts one `feedback` row per changed field with old/new values, context, and `model_confidence_at_time` from the parse confidence. Drift `Value<String?>` distinguishes "not edited" from "cleared". Also new `watchDetail(id)` (same join as the list) + `transactionDetailProvider` family and `TransactionDetail` model with `parseConfidence` extraction (`_parseConfidenceOf`, fails soft to null on malformed json).
- Files: lib/features/transactions/transaction_detail_screen.dart (new), lib/features/transactions/transactions_screen.dart (row onTap), lib/features/transactions/transactions_providers.dart, lib/data/repositories/transaction_repository.dart, test/features/transactions/transaction_detail_screen_test.dart (new), TASKS.md, WORKLOG.md.
- Tests written: repository — one feedback row per changed field with correct shape (old/new/context/model_confidence_at_time/created_at); no-op edits write neither update nor feedback; atomicity proven by an injected feedback-id factory that collides on the SECOND staged field, so the insert throws after the update and the first feedback insert already executed — asserts both rolled back. Widget — §6.2 field rendering incl. confidence trail; edit category+description → save → both persisted with 2 'detail_edit' feedback rows; tapping a list row navigates to the detail screen.
- Evidence caveat: same as T-037 — no runnable Flutter or GitNexus in this sandbox, so analyze/test/impact/detect_changes are deferred to @codex verification; tests written but unexecuted. T-038 → In Review.
- Decisions: feedback ids default to `fb_<txnId>_<field>_<micros>` with an injectable factory (needed for the atomicity test and future dedup); `updateWithFeedback` returns the number of feedback rows written so the UI can distinguish "Saved" from "No changes to save"; kept the deferred "Suppressed duplicates" dev screen out of scope again (noted in T-036) — the detail screen shows `duplicate_of_txn_id` only implicitly (suppressed rows never appear in the list).
- Open questions: none.
- Next: T-039 (seed-map categorization + rules engine) is the remaining T-036-dependent Ready task; @codex should run the verification pass over T-037+T-038 first.

## 2026-07-07 @claude — T-037

- Did: implemented manual transaction entry. New `ManualEntryScreen` (form: Spent/Received `SegmentedButton`, amount field with ₹ prefix and >0 validator, category `DropdownButtonFormField` (defaults Uncategorized), optional description, `showDatePicker` date defaulting to today, Save `FilledButton` with error snackbar path); reached via a new FAB on `TransactionsScreen`. Channel is fixed 'cash' per AC. New `TransactionRepository.insertManual(ManualTransactionDraft, {clock})` persists `parse_source='manual'`, `status='confirmed'`, confidence 1.0, deterministic-per-clock id `txn_manual_<micros>`; returns the id. New `CategoryRepository.watchAll()` (sort-order stream) + `categoryRepositoryProvider`; new `categoryListProvider` in transactions_providers. `_toListItem` display-name fallback chain gains `?? txn.description` at the end (parsed rows always have merchant/VPA or stay 'Unknown' — description is null for them — so parsed-row rendering is unchanged; manual rows show their description).
- Files: lib/features/transactions/manual_entry_screen.dart (new), lib/features/transactions/transactions_screen.dart, lib/features/transactions/transactions_providers.dart, lib/data/repositories/transaction_repository.dart, lib/data/repositories/category_repository.dart (new), test/features/transactions/manual_entry_screen_test.dart (new), TASKS.md, WORKLOG.md.
- Tests written: repository test (insertManual row shape: manual/confirmed/cash/category/description/no-sms-provenance, plus renders through `watchTransactions` with description as display name and category display data resolved); widget tests for save-persists, credit direction, validation-blocks-save (nothing persisted), and FAB navigation from the transactions list.
- Evidence caveat: this sandbox cannot run Flutter (repo-local SDK is a different architecture; SDK download blocked by sandbox network policy) and the GitNexus CLI cannot start (npx install killed at sandbox timeout) — so the CLAUDE.md impact/detect_changes preflights and `flutter analyze`/`flutter test` could not be run, same limitation logged for the T-036 review and the 2026-07-05 reviews. All five tests are written but unexecuted. T-037 goes to In Review for an @codex toolchain verification pass (T-029→T-030 pattern) instead of Done.
- Decisions: category picker lives in a new `CategoryRepository` rather than widening `TransactionRepository`, since T-041 (category manager) will need the same surface; `ManualTransactionDraft.channel` defaults to cash but is a parameter so a future channel selector needs no repository change; date-only picker stores midnight local converted to UTC (consistent with how parsed SMS timestamps are already stored as UTC millis).
- Open questions: none.
- Next: T-038 (transaction detail + edit writes feedback rows) or T-039 (categorization) — both unblocked; @codex should verify T-037 first since T-038 touches the same screens.

## 2026-07-07 @claude — Review T-036

- Did: reviewed T-036 (schema v2: counterparty_vpa + duplicate_of_txn_id + category in list items) against ADR 0003 and the COLLABORATION.md review checklist.
- Evidence: read the full working-tree diff — `transactions_table.dart` (both columns + `idx_transactions_duplicate_of_txn_id`), `database.dart` (`schemaVersion=2`, `onUpgrade` addColumn/createIndex + `_backfillDuplicateLinks`), new `lib/data/dedup/duplicate_match_rule.dart`, `duplicate_suppressor.dart`/`sms_ingestion.dart` (link written instead of `isDeleted`; candidates exclude deleted and already-linked rows; write-time `merchantRaw??counterpartyVpa` fold removed), `transaction_repository.dart` (visibility predicate `is_deleted=0 AND duplicate_of_txn_id IS NULL`; presentation-time merchant→VPA fallback), `category_visuals.dart` normalizer deletion + `transactions_screen.dart` direct id/icon usage, `transaction_export.dart` new export fields, `docs/schema.md` migration log, and all five touched/new test files. The v2 migration test is non-vacuous: builds a real v1 sqlite3 file, asserts `user_version=2`, both columns, the index, unique-match echo conversion (`duplicate_of_txn_id` set + `is_deleted` cleared), conservative orphan retention, no `counterparty_vpa` backfill, and row preservation.
- Environment caveat: could not re-run `flutter test`/`flutter analyze` here (repo-local Flutter binary is a different architecture) and GitNexus CLI could not start (npx install killed by sandbox timeout), so the review relies on reading source plus @codex's logged evidence (64 passed / 2 skipped; analyze clean; detect_changes HIGH reviewed as expected surface). Same limitation as the 2026-07-05 T-003/T-004 review.
- Decisions: T-036 → Review: PASS, moved to Done. Non-blocking finding recorded on the board: `_backfillDuplicateLinks` candidate query excludes `is_deleted=1` but not rows already converted to links in the same pass, so a later echo could match a just-converted echo; the >1-match ambiguity branch keeps it conservative (row stays suppressed) rather than corrupting — revisit only if a real device migration logs unresolved rows.
- Next: T-037, T-038, T-039, T-041 are unblocked; proceeding with T-037 (manual transaction entry).

## 2026-07-07 @codex — T-036

- Did: implemented Drift schema v2 per ADR 0003. `transactions` gains `counterparty_vpa` (nullable, independent of `merchant_raw`) and `duplicate_of_txn_id` (nullable, self-referencing, indexed). `is_deleted` reverts to user-delete-only semantics; `DuplicateSuppressor` now returns which existing row matched and `SmsIngestor` writes the `duplicate_of_txn_id` link instead of setting `is_deleted`. Removed the `merchantRaw ?? counterpartyVpa` write-time fallback; `TransactionRepository._toListItem` now does the merchant→VPA fallback at presentation time instead. `TransactionListItem` gains `categoryId`/`categoryIcon` resolved in the same join query; `transactions_screen.dart` tiles now call `CategoryVisuals.color(item.categoryId)`/`icon(item.categoryIcon)` directly, so the old name→id normalizer (`colorForName`/`iconForName`/`_idForName`) is deleted from `CategoryVisuals`. `watchTransactions()` excludes rows where `is_deleted = 1 OR duplicate_of_txn_id IS NOT NULL`. `TransactionJsonExporter` gains `counterparty_vpa`/`duplicate_of_txn_id` in its reconciliation export (per the ADR's consequences).
- Migration: `AppDatabase.schemaVersion` is 2; `onUpgrade` adds both columns + the index, then `_backfillDuplicateLinks()` re-runs the pairing rule (direction, amount tolerance, 10-minute window, ref id or counterparty key) against every v1 `is_deleted=1` row; a unique match sets `duplicate_of_txn_id` and clears `is_deleted`, otherwise the row stays `is_deleted=1` and an unresolved count is logged (conservative, per ADR). No backfill for `counterparty_vpa` (unreconstructable provenance, matches ADR). The pairing rule itself was extracted to a new pure `DuplicateMatchRule` (`lib/data/dedup/duplicate_match_rule.dart`) shared by `DuplicateSuppressor` (live ingestion) and the migration backfill, so both use identical matching semantics — this also fixed a real bug caught by the ingestion test: once ingestion stopped folding `counterpartyVpa` into `merchantRaw`, the existing-row counterparty key has to read `existing.counterpartyVpa` first, not just `existing.merchantRaw`.
- Files: `lib/data/db/tables/transactions_table.dart`, `lib/data/db/database.dart`, `lib/data/dedup/duplicate_match_rule.dart` (new), `lib/capture/duplicate_suppressor.dart`, `lib/capture/sms_ingestion.dart`, `lib/data/repositories/transaction_repository.dart`, `lib/core/theme/category_visuals.dart`, `lib/features/transactions/transactions_screen.dart`, `lib/features/dev/transaction_export.dart`, `docs/schema.md`, `test/capture/duplicate_suppressor_test.dart`, `test/capture/sms_ingestion_test.dart`, `test/features/transactions/transactions_screen_test.dart`, `test/features/dashboard/dashboard_screen_test.dart`, `test/data/db/app_database_v2_migration_test.dart` (new), `TASKS.md`, `WORKLOG.md`.
- Evidence: `dart run build_runner build --delete-conflicting-outputs` regenerated `database.g.dart` clean. `flutter analyze --no-pub` clean (1 pre-existing unrelated lint in `unparsed_sms_screen.dart`). Full `flutter test --no-pub --concurrency=1`: 64 passed, 2 skipped (scratch dashboard debug test; host SQLCipher migration skip — the new `app_database_v2_migration_test.dart` does not need SQLCipher since it builds the v1 fixture with plain `sqlite3` and opens it via `NativeDatabase`, so it runs unskipped and asserts columns/index/backfill/data-preservation). GitNexus `detect_changes(scope: all)` on a freshly re-analyzed index reports HIGH risk across 51 changed symbols / 15 affected processes — expected given the scope (write path, migration, read path, and two UI call sites all touched together for one ADR); reviewed the affected-process list and all of it maps to the intended change surface, no surprises.
- Decisions: kept the shared matching logic in a new `lib/data/dedup/` module (data layer) rather than having `database.dart` import from `lib/capture/` (would invert the existing capture→data dependency direction) or duplicating the rule inline in the migration. Deferred the ADR's "Suppressed duplicates" dev screen (primary+echo side by side, un-suppress action) — not in T-036's AC; flagging as a natural follow-up once the detail screen (T-038) needs the same duplicate-of relationship.
- Open questions: none.
- Next: T-037/T-039/T-041 unblocked (Depends: T-036); moving T-036 to In Review for @claude.

## 2026-07-07 @codex — T-031

- Did: added shared `formatInr()` for INR strings with Indian digit grouping and two decimals, then adopted it in dashboard totals and transaction-list amount text. The existing tabular-figure styling remains on both money text sites; transaction-list credit/debit signs stay outside the formatter.
- Files: `lib/core/format.dart`, `lib/features/dashboard/dashboard_screen.dart`, `lib/features/transactions/transactions_screen.dart`, `test/core/format_test.dart`, `test/features/dashboard/dashboard_screen_test.dart`, `test/features/transactions/transactions_screen_test.dart`, `TASKS.md`, `WORKLOG.md`.
- Evidence: GitNexus pre-edit impact LOW for `_TotalCard` (3 direct dependents, 0 processes), LOW for `_TransactionTile` (2 direct dependents, 0 processes), and LOW for `monthDirectionTotalsProvider` (0 dependents). `flutter analyze --no-pub` clean with repo-local `HOME`. Targeted `flutter test --no-pub test/core/format_test.dart test/features/dashboard/dashboard_screen_test.dart test/features/transactions/transactions_screen_test.dart --concurrency=1` passed 7/7 outside sandbox after the sandbox blocked Flutter's local test-runner socket bind. GitNexus `detect_changes(scope: all)` reported LOW risk, 0 affected processes.
- Decisions: kept `formatInr()` dependency-free and in `lib/core/format.dart`; did not introduce locale/intl setup for this narrow helper. Updated widget assertions to lakh/crore-shaped values so the regression signal covers Indian grouping, not only the currency symbol.
- Open questions: none.
- Next: none from T-031. Note: T-032 icon-compression changes are present separately in the worktree.

## 2026-07-06 @codex — T-030

- Did: verified the T-029 dark-first design-system retrofit in the local toolchain and fixed the one regression it exposed. The onboarding screen overflowed at the default 800x600 widget-test viewport and left the "Grant SMS access" button partly off-screen; `OnboardingScreen` now uses a scroll-safe body with compact illustration/spacing/typography at short heights while preserving test-visible strings and permission behavior.
- Files: `lib/features/onboarding/onboarding_screen.dart`, `TASKS.md`, `WORKLOG.md`.
- Evidence: GitNexus pre-edit impact was LOW for `OnboardingScreen` (3 direct upstream dependents, 1 affected process: onboarding test flow) and LOW for `_PermissionBody` (2 direct upstream dependents, 0 affected processes). `flutter analyze` clean. Targeted `flutter test test/features/onboarding/onboarding_screen_test.dart --concurrency=1` passed. Full `flutter test --concurrency=1` passed: 57 passed, 2 skipped (scratch dashboard debug test and host SQLCipher migration skip). Android `./gradlew :app:testDebugUnitTest` BUILD SUCCESSFUL: 90 actionable tasks, 12 executed, 78 up-to-date. GitNexus `detect_changes(scope: all)` reported MEDIUM risk limited to `lib/features/onboarding/onboarding_screen.dart` and the `Main → OnboardingScreen` process.
- Decisions: treated the off-screen action as real design fallout from T-029 rather than weakening tests; kept the fix scoped to layout responsiveness, not copy or permission state behavior. Ran Gradle with `GRADLE_USER_HOME` under `.tooling/_home/.gradle` to avoid writing outside the workspace.
- Open questions: none.
- Next: T-031 shared `formatInr()` currency formatter.

## 2026-07-06 23:50 @claude — Design system (dark-first) + theme implementation + screen retrofit

- Did: established the PaisaTrack design system per the human's direction (dark-first fintech anchored on the app icon: near-black green surfaces, emerald primary, gold accent; light as an equal derived variant) and retrofitted all existing screens.
- Docs: new `docs/design-system.md` — principles, color/typography/spacing/shape tokens, money & status semantics (debit/credit colors on amounts only, debit ≠ error, warning for degraded states), two-tier iconography (brand PNG illustrations hero-only; Material icons for UI; fixed per-category hues), motion, accessibility, component recipes, and a UI-PR review checklist. `docs/architecture.md` links it as binding.
- Code (new): `lib/core/theme/app_tokens.dart` (AppColorTokens/AppSpacing/AppRadius/AppDurations/AppIllustrations), `lib/core/theme/app_theme.dart` (Material 3 dark+light ThemeData from tokens; tonal surfaces, no shadows; tabular-figure helper for money text), `lib/core/theme/paisa_colors.dart` (ThemeExtension for credit/debit/warning/gold/info with brightness-aware fallback so bare-MaterialApp widget tests keep working), `lib/core/theme/category_visuals.dart` (seed icon-name → IconData, category-id → fixed hue, plus name→id normalizer for list rows that only carry categoryName).
- Code (retrofit, styling only — all test-visible strings and amount formats unchanged): `app.dart` (AppTheme light/dark, themeMode dark), dashboard (icon-tile summary cards, semantic colors, tabular amounts), transactions (design-system tile: category avatar, signed colored amount), home_shell (selected-icon variants), onboarding (hero illustration with errorBuilder fallback, warning-styled degraded notices instead of bare error text), unparsed dev screen (leading icon, secondary body style).
- Deliberately deferred: Indian digit grouping `formatInr()` (changes rendered strings → lands with widget-test updates in Phase 2); category_id/icon in `TransactionListItem` (repository query change, tracked as follow-up — name normalizer is the interim); PNG asset compression (~14 MB total at 1254×1254; resize ≤512px/WebP before Phase 5 release).
- Caveat: `flutter analyze` / `flutter test` NOT run here (no Flutter toolchain in this environment). Self-review covered imports, Dart 3.4 syntax, and Flutter 3.44 API availability (`withValues`, `CardThemeData`, `surfaceContainer*` verified present in `.tooling/flutter`), but run both locally plus `detect_changes()` before commit. Widget tests assert text finders only, so styling changes should be green, and onboarding's `Image.asset` has an errorBuilder guard.
- Next: local verification; then Phase 2 UI tasks (settings theme toggle switching themeMode to system, formatInr + test updates, empty-state redesigns per design-system §5).

## 2026-07-07 @claude — PHASE P1 EXIT: PASS (T-034 complete)

- Result: **Phase 1 exit criterion met — 94.4% statement coverage (388/411 rows) in the backfill window 2026-04-06..2026-07-06, against the >=90% requirement.** This closes the sole blocker from the T-027 exit review; Phase 1 (Capture MVP) is PASS.
- Evidence: human ran the debug transaction export on-device (400 parsed transactions, all `parse_source=template`, 4 suppressed duplicates) and supplied 3 IndusInd statement XLSXes. `scripts/reconcile_statement.py` (fixed for device exports: `case`→`id` fallback): 389/400 transactions matched (381 exact ref / 7 amount+date / 1 unique-amount), zero amount/direction contradictions — stronger than the hand-verification the criterion asked for, since every match is ref- or balance-anchored. 11 unmatched transactions have no candidates in this account's statement — consistent with the earlier fixture finding that VPA-template messages belong to a different linked IndusInd account.
- Known gap (filed T-047): all 23 uncovered statement rows are Transfer Credits — NEFT salary (`SAL ... RAPIPAY`), ACH dividend credits, quarterly interest, MF redemptions, IMPS P2A. No uncovered debits. Either these SMS shapes lack templates (check the dev Unparsed screen) or the bank sends no SMS for them (interest almost certainly not) — T-047 resolves which, fixture-first.
- Row-level report: BankStatement/coverage_report.md (gitignored; contains bank data).
- Next: Phase 2 queue (T-035 onward) proceeds with Phase 1 formally closed; T-047 can run in parallel since it's pure template/fixture work.

## 2026-07-07 @claude — T-034 tooling: debug-only transactions JSON export

- Did: added the missing piece for the T-034 device coverage run — a way to get parsed transactions out of the encrypted on-device DB. `lib/features/dev/transaction_export.dart`: `TransactionJsonExporter.serializeAll()` emits every transaction row (including suppressed duplicates, flagged `is_deleted`) in the reconciliation schema consumed by `scripts/reconcile_statement.py --transactions`; `exportTo()` writes pretty-printed JSON; `transactionJsonExportProvider` targets the app-private documents dir via path_provider (already a dependency). Dev screen gained an app-bar download button guarded by `kDebugMode` (compiled out of release) with success/failure snackbars.
- Privacy: plain JSON lands only in `/data/data/com.paisatrack/app_flutter/` (app-private, never external storage); retrieval requires `adb run-as`, which only works on debuggable builds. This is developer tooling, distinct from the Phase 2 user-facing encrypted export (T-043).
- Tests: `test/features/dev/transaction_export_test.dart` — serialization schema (incl. `is_deleted` passthrough) and file round-trip on an in-memory DB.
- Caveat: `flutter analyze`/`flutter test` not run here (no toolchain in this environment); verify locally before relying on it — @codex can fold verification into the next task pickup.
- Device procedure: debug build → grant SMS → let backfill finish → Dev tab → download icon → `adb shell run-as com.paisatrack cat app_flutter/transactions_export.json > export.json` → `python3 scripts/reconcile_statement.py --statements 'BankStatement/*.xlsx*' --transactions export.json --out BankStatement/coverage_report.md`.

## 2026-07-07 @claude — T-034 partial: fixture↔statement reconciliation tooling + first run

- Did: built `scripts/reconcile_statement.py` to reconcile IndusInd statement XLSX exports (BankStatement/, gitignored — contains PAN/address; never commit) against SMS data. Matching ladder: ref containment → amount+direction+balance → amount+direction+date → amount+direction only-if-unique. Supports `--fixtures` (committed sanitized subset) today and `--transactions` (JSON export of the on-device parsed DB) for the real T-034 device run.
- First run (3 statements, Apr 2025–Jul 2026, 2,445 deduped rows vs 37 positive IndusInd fixtures): **22/37 confirmed on-statement with exactly matching amount+direction (19 by exact ref); zero contradictions** — no fixture matched a statement row with a different amount/direction, i.e. no evidence of misparse in the fixture set. 7 fixtures (all `vpadebit`/`vpacredit`/`credit_04` shapes) have NO amount candidates anywhere in the statement — the "VPA linked to A/C" template messages almost certainly belong to a different linked IndusInd account, not statement account …6265. 8 are unpinnable due to sanitization artifacts, not parser issues: autopay UMN refs masked to `XXXX…`, and every fixture's `received_at`/`ts` collapsed to the 2026-07-06 pull date, killing date matching.
- Fixture-authoring follow-ups (for the next sanitization pass): preserve original SMS timestamps (they are not PII) and mask refs deterministically (e.g. keep last 4) so statement reconciliation stays possible.
- T-034 remains open: this proves fixture-side precision, but the >=90% statement→SMS coverage criterion needs the on-device parsed DB (fixtures are a curated subset, so coverage cannot be computed from them). Run the app backfill, export transactions to JSON, then `python3 scripts/reconcile_statement.py --statements 'BankStatement/*.xlsx*' --transactions <export.json> --out BankStatement/coverage_report.md`.
- Report (row-level, uncommitted): BankStatement/reconciliation_report.md.

## 2026-07-07 @claude — Phase 2 grooming (T-034..T-046 filed)

- Did: groomed the Phase 2 (Usable Tracker) queue on TASKS.md with ordered, AC'd tasks: T-035 ADR 0003 spec (dedup `duplicate_of` link + `counterparty_vpa` column — fixes the T-025 `is_deleted` overload and merchantRaw fallback), T-036 schema v2 migration (also adds categoryId/icon to `TransactionListItem`, retiring the CategoryVisuals name→id normalizer), T-037 manual entry, T-038 detail+feedback, T-039 seed-map categorizer + rules, T-040 decision policy v1, T-041 category manager, T-042 settings v1 (incl. theme toggle per design-system §10 and "Delete everything"), T-043 encrypted export/import (free deps only per ADR 0002), T-044 ask-now notifications, T-045 weekly review, T-046 Phase 2 exit review.
- Filed T-034 (@human, Blocked): the outstanding Phase 1 bank-statement reconciliation from T-027 — blocks Phase 1 exit PASS declaration only; Phase 2 build work proceeds in parallel per T-027's assessment.
- Sequencing rationale: schema rework (T-035/T-036) goes first because detail/categorizer/category-manager all touch the same rows and should not build on the `is_deleted` dedup hack; policy (T-040) gates both interruption surfaces (T-044/T-045).
- Next: @codex picks T-036 after @human approves the ADR (T-035 is mine and is next up); @human runs T-034 whenever convenient.

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
