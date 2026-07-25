# Full-codebase review — 2026-07-25

Scope: all of `lib/` (29,188 lines, 106 files), `android/app/src/main/kotlin`,
and the product docs (`README`, `PLAN`, `docs/architecture.md`, `docs/privacy.md`,
`docs/schema.md`, `docs/design-system.md`, `docs/development.md`, ADRs 0001–0008).
Findings are stated against documented intent, not personal preference.

Not verified in this session: the bundled Flutter SDK is macOS-only, so
`analyze`/`test` were not re-run here. The referenced 410-test pass is taken as
given. Every finding below is a static read of the source.

## Summary

The architecture matches the docs unusually well: local-first, typed rejections
instead of silent guesses, evidence preserved separately from user corrections,
deterministic assistant rendering, token-disciplined theming, and migrations
that repair rather than wipe. Defects cluster in three places — **background
execution** (the nightly job probably cannot open the database at all), **the
truthfulness of the numbers on Home** (a silent fallback path can display wrong
totals as fact), and **the reach of search** (search only sees the loaded page).
Accessibility contrast in the light theme fails WCAG AA for the app's most
important color signal.

## Critical issues

| # | File | Line | Issue | Severity |
|---|------|------|-------|----------|
| 1 | `lib/intelligence/nightly_job.dart` | 172–208 | Nightly WorkManager isolate calls `AndroidKeystoreDatabasePassphraseProvider().getPassphrase()`, but `com.paisatrack/database_passphrase` is registered only in `MainActivity.configureFlutterEngine` (`MainActivity.kt:48–79`). A background engine never runs that code, so `invokeMethod` throws `MissingPluginException` — which `getPassphrase` does not catch (it catches only `PlatformException`, `database_cipher.dart:50`). The entire nightly pipeline, including **`purgeExpiredRawSms`**, likely never runs headless. `docs/privacy.md`'s "Raw SMS retention is capped by `AppConstants.rawSmsRetentionDays`" depends on it. | 🔴 Critical |
| 2 | `lib/features/dashboard/dashboard_providers.dart` | 209, 272, 325, 432, 482 | Every money metric reads `dashboardAggregateProvider.valueOrNull` and, when null, silently recomputes from `transactionListProvider` — the newest **100** rows. `valueOrNull` is null while loading *and on error*, so a failed aggregate query renders a plausible, wrong "spent this period" with no indication. In a numbers-first product this is a correctness bug, not a UI nit. | 🔴 Critical |
| 3 | `lib/features/transactions/transactions_screen.dart` | 127–160, 291 | Search and all filters run in Dart over the already-loaded window (`_applyFilters` on `transactionListProvider`, page size 100). Searching a merchant older than the loaded window returns "No matches" — and the result set changes depending on how many times the user tapped "Load older transactions". Contradicts `docs/development.md` ("keep watched feeds bounded, aggregate full-history metrics in SQL"). | 🔴 Critical |
| 4 | `lib/core/crypto/database_cipher.dart` | 44–60 | On `PlatformException`, `getPassphrase` clears the stored passphrase and requests a new one; `DatabasePassphraseStore.getOrCreate` (`DatabasePassphraseStore.kt:33–45`) does the same on any decrypt failure. A transient Keystore fault therefore **generates a fresh key against an existing SQLCipher file**, making all data permanently unreadable, with no user-facing explanation or recovery path (and no prompt to restore a backup). | 🔴 Critical |

## Suggestions

| # | File | Line | Suggestion | Category |
|---|------|------|------------|----------|
| 5 | `lib/intelligence/assistant/query_engine.dart` | 79–146 | `_total`/`_breakdown`/`_comparison` materialize every matching row and sum in Dart; `_comparison` does it twice. "How much did I spend this year" loads the year into memory. Move to `SUM`/`GROUP BY`, reusing `DashboardRepository`'s predicates so both surfaces can't drift apart. | Performance |
| 6 | `lib/capture/sms_ingestion.dart` | 313–315 | `_countAskedToday` uses a **UTC** day boundary. For an India-first app the daily ask budget resets at 05:30 IST, and "asked today" disagrees with every date shown in the UI (which is local). Use the local day. | Correctness |
| 7 | `EmbedderBridge.kt:63–66`, `LlmBridge.kt:67` | — | The download streams `input.copyTo(output)` with no byte cap and no `responseCode` check; size/SHA are verified only after the full body lands. A misbehaving or hijacked endpoint can fill cache/app storage first. Cap at `PINNED_MODEL_SIZE` (+slack) and abort early; reject non-2xx/206 before reading. | Security |
| 8 | `android/.../capture/SmsFilter.kt` | 24–50 | Beyond the known allowlist gap (T-108), the reject markers are too broad: `"do not share"` appears in many banks' *transaction* alerts ("never share your OTP/PIN"), and `"offer"`, `"win "`, `"congratulations"` appear in legitimate credit/cashback messages. Every false reject is invisible — the message never reaches `raw_sms` or the unparsed dev screen. Require OTP markers to co-occur with an OTP shape (`\b\d{4,8}\b` + no debit/credit verb), and log a filtered-count metric (no bodies). | Correctness |
| 9 | `lib/capture/sms_ingestion.dart` | 106–112, 236–252 | `_ingestSafely` and `ingestBatch` swallow every error; `SmsBatchIngestResult.failed` is counted for imports but live-capture failures vanish entirely. Surface a persistent failed-ingest counter (dev screen at minimum) so silent capture loss is detectable. | Observability |
| 10 | `lib/data/db/database.dart` | 168–214 | `_backfillDuplicateLinks` re-selects **all** non-deleted transactions inside a loop over suppressed rows — O(n×m) with full materialization during a migration. Only affects v1 installs, but a single indexed query per row (ts window + direction) is a small change. | Performance |
| 11 | `lib/features/settings/settings_screen.dart` | 285 | `'Delete failed: $error'` puts raw exception text (potentially file paths) in a user-facing snackbar. Log the detail, show a stable message — the pattern already used for settings load errors at line 220. | Privacy |
| 12 | `lib/core/crypto/database_cipher.dart` | 90–91 | `PRAGMA key = '…'` is built by string escaping. The passphrase is app-generated base64 so there is no live injection path, but a bound parameter (`PRAGMA key = ?`) removes the class of bug entirely and survives a future "user-chosen passphrase" feature. | Security (defense in depth) |
| 13 | `lib/capture/llm_extractor.dart` | 64–68 | Model-supplied `ts` is accepted anywhere from 2000-01-01 to receipt+1d. A hallucinated 2003 timestamp silently lands a transaction years back in history. Clamp to `receivedAt ± 7d`. | Correctness |
| 14 | `lib/core/format.dart` | 2–23 | `formatInr` produces `₹NaN.NaN` for NaN/Infinity (reachable from a corrupt/imported amount). Guard and render an em dash. | Robustness |
| 15 | `lib/features/backup/encrypted_backup_service.dart` | 296–317 | Import honors attacker-supplied Argon2 parameters up to 256 MiB × 4 lanes before authentication, so a malicious `.ptrack` can OOM the app. User-selected file, so low risk — but the bound could be tightened to the export profile plus a small margin. | Security |

## Design critique

Measured against `docs/design-system.md`, which is specific enough to audit
against — a real strength.

**Contrast (computed, WCAG 2.1 AA):**

| Pair | Ratio | Verdict |
|---|---|---|
| `creditLight #0E9F6E` on white | **3.39:1** | Fails 4.5:1 for text — and this token is also the light theme's `primary` (`app_theme.dart:47`), so filled-button labels fail too |
| `debitLight #D64545` on white | **4.38:1** | Marginally fails |
| `royalBlue #3B82F6` on white | 3.68:1 | Fails for text; OK for ≥24px/icons |
| `gold #E8B54D` on white | 1.88:1 | Unusable for anything but decoration in light theme |
| `lightOutline #D5E2DD` on white | 1.33:1 | Card borders are the *only* separation from `#F6FAF8` background; below the 3:1 non-text minimum |
| `darkOutline #2E3D38` on dark surface | 1.51:1 | Same issue in dark theme |

Dark-theme text/money colors all pass comfortably (6.9–10.3:1). The light theme
is the weak variant, despite the doc's "Dark and light themes are equal
requirements." Because debit/credit is signalled by color on the amount, this
is also a color-only-signal risk for the doc's "Color is never the only status
signal" rule — the `+`/`-` sign carries it, which is thin.

**Other design findings:**

1. **Home has no loading or error state.** `dashboard_screen.dart` renders only
   `EmptyStateView`; no `ErrorStateView`, no skeleton. Every other list screen
   has all five states. Combined with critical issue #2, the home screen's
   failure mode is "show wrong numbers confidently."
2. **The most important recovery action is under-sized.** The "Grant SMS
   access" button in `_SmsPermissionBanner` sets `minimumSize: Size(0,0)` and
   `tapTargetSize: shrinkWrap` (`dashboard_screen.dart:476–477`) — below the
   documented 48×48 minimum, on the control that turns the product on.
3. **Long-press multi-select has no visible alternative**
   (`transactions_screen.dart:380`). The doc explicitly requires one. Add a
   "Select" action to the app bar.
4. **Two navigation models coexist.** Home pushes new `TransactionsScreen` /
   `WeeklyReviewScreen` instances that also exist as `HomeShell` tabs. Users
   reach the same screen in two states (with/without back button, with/without
   FAB, separate scroll and filter state). Tap-through should switch the tab
   and hand it a filter, not push a duplicate.
5. **Screen-reader coverage is thin.** Six `Semantics(` calls across four files.
   Icon-only controls mostly have tooltips (24), which helps, but amounts,
   direction, and review status have no explicit labels — `-₹1,200.00` will be
   announced awkwardly, and the doc's "TalkBack order follows visual reading
   order" is unverified. T-120 already tracks the test side; the labels
   themselves are still missing.
6. **Inconsistent loading treatment.** `ListLoadingSkeleton` on transactions /
   review / insights / recurring; bare `CircularProgressIndicator` in settings,
   payee labels, category manager, payment sources, assistant.
7. **Period picker doesn't show what's currently selected** — seven options, no
   check mark (`dashboard_screen.dart:210–265`).
8. **Destructive confirm isn't styled destructive.** "Delete everything" uses a
   default `FilledButton`; consequence text is good, visual weight isn't.

## What looks good

- Privacy architecture is coherent and enforced in code, not just prose:
  retention-limited `raw_sms`, evidence preserved separately from corrections,
  `kDebugMode`-gated exports, SAF-only document access, no cloud path.
- `docs/` genuinely describes this codebase — rare, and it made this review
  auditable. The ADRs carry the reasoning the code omits.
- Duplicate suppression via `duplicate_of_txn_id` instead of deletion (ADR
  0003), and the v1→v2 backfill that refuses to guess.
- v6/v7 payment-source repair migrations with named regression fixtures, and
  the "never clear app data" discipline.
- Assistant grounding: model output is confined to intent classification;
  `AnswerRenderer` interpolates only deterministic query fields.
- `SmsIngestor.ingest` checking for an existing transaction *before* the raw
  upsert, so re-import can't resurrect purged bodies or overwrite user edits.
- Theme token discipline: no stray `Colors.red`/`Color(0x…)` outside
  `app_tokens.dart`.

## Verdict

**Request changes.** Items 1–4 should land before the release-hardening work in
`TASKS.md` — #1 silently voids a documented privacy guarantee, #2 and #3 make
the product's core numbers untrustworthy, and #4 is unrecoverable data loss.
Items 5–8 and the light-theme contrast fix are the next tier. Suggested new
tasks: T-121 (background-isolate passphrase channel), T-122 (dashboard
aggregate as the single source with real loading/error states), T-123 (SQL-side
search and filters), T-124 (Keystore key-loss recovery UX), T-125 (light-theme
contrast + touch-target audit).
