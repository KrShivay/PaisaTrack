# PaisaTrack — Project Status Report

Reviewed 2026-07-09 by @claude, against PLAN.md, TASKS.md, README.md, docs/,
and WORKLOG.md.

## 1. Where the project stands

PaisaTrack is in **Phase 2 (Usable Tracker)**.

Phase 0 is complete: scaffold, encrypted Drift database, Keystore-backed
SQLCipher passphrase, category seed loading, fixture harness, CI guardrails, and
Android API 26 minimum are in place.

Phase 1 is complete and passed exit review on 2026-07-07. The app captures SMS
through native Android filtering, performs live ingestion and one-time backfill,
parses real bank/wallet templates, suppresses paired duplicate notifications,
and shows captured transactions in the dashboard/list/dev views. The original
Phase 1 reconciliation matched **388/411 statement rows (94.4%)** with zero
amount/direction contradictions.

Phase 2 build work is complete; only the exit review remains. Landed work:

- T-035/T-036: duplicate/counterparty ADR and schema v2 implementation.
- T-037: manual transaction entry, verified and Done.
- T-038: transaction detail/edit writes feedback rows, verified and Done.
- T-039: seed-map categorization and rules engine, verified and Done.
- T-040: Decision policy v1 wired into ingest/status writes, reviewed and Done.
- T-041: category manager.
- T-042: settings v1 and local data reset.
- T-043: encrypted export/import.
- T-044: ask-now notifications — top-3 category action buttons + free-text
  remote input, app-killed-safe response persistence, one-write
  rule/feedback/status correction, ask budget from Settings, income-side-only
  credit categories. Done (tests human-verified).
- T-045: weekly review tab over `needs_review` with swipe-confirm /
  tap-correct, one-write corrections, empty state. Done.
- T-047: IndusInd NEFT/ACH-credit templates, fixture/SMS-dump coverage reported
  at **407/411 statement rows (99.03%)**; final device export folds into T-046.

## 2. Current build goal

Phase 2 is built. The remaining step to close the phase:

1. Run T-046 Phase 2 exit review against the PLAN §9 criteria (daily-usable,
   ≤2 asks/day, correction→rule→auto-label demo, export/wipe/import round-trip)
   using T-035..T-045 evidence, then move to Phase 3 grooming.

## 3. Architecture summary

The app is local-first:

- Android native code filters and captures candidate SMS messages.
- Dart capture code parses messages through JSON template registries.
- `SmsIngestor` writes raw SMS and normalized transaction rows in encrypted
  SQLite, suppressing linked duplicates instead of deleting them.
- Enrichment applies user rules and a bundled seed category map, then a static
  decision policy sets each row's status (`auto` / `asked` / `needs_review`).
- Ask-now notifications and the weekly review tab turn `asked` / `needs_review`
  rows into confirmed transactions; both correct through one write path
  (`correctWithRule`: rule + feedback + status in a single DB transaction).
- Riverpod providers own database lifetime, settings, screens, and test
  overrides.
- Settings owns theme choice, ask budget, reset, and encrypted backup/import.

The normalized transaction record remains the contract between capture,
enrichment, repositories, and UI.

## 4. Quality and privacy notes

- The privacy rule is stronger than "cloud off by default": there is no cloud
  inference path. ADR 0002 requires free, on-device-only intelligence.
- Raw SMS bodies are capture inputs only. They must not be committed, logged in
  release builds, or written to plaintext exports.
- Database encryption uses SQLCipher with passphrase material wrapped by Android
  Keystore.
- Backup/import uses passphrase-encrypted JSON (`Argon2id` + `AES-256-GCM`) and
  keeps plaintext domain JSON in memory only.
- Schema v2 separates user deletion (`is_deleted`) from duplicate suppression
  (`duplicate_of_txn_id`) and stores `counterparty_vpa` separately from merchant
  text.

## 5. Known risks and gaps

- T-044/T-045 tests are **human-verified**, not re-run in this sandbox (the
  repo-local Flutter SDK is wrong-arch for the Linux sandbox). A canonical
  full-suite `flutter test` re-run is folded into the T-046 exit evidence.
- GitNexus reported the index stale (behind HEAD) during this review; use the
  task board and worklog as fresher status until the index is refreshed.
- Ask-now app-killed delivery relies on SharedPreferences persistence — the
  end-to-end killed-state path is covered by unit tests and a manual QA note,
  not an instrumented device test.
- T-047's 99.03% coverage is from fixture/SMS-dump simulation; the final device
  export confirmation is still outstanding, to be captured in T-046.

## 6. Bottom line

The project is no longer a foundation scaffold. It is a working local-first SMS
finance tracker with its full Phase 2 build complete: capture, enrichment,
decision policy, and both correction surfaces (ask-now + weekly review) are
landed. The one remaining step before Phase 3 is the T-046 Phase 2 exit review.
