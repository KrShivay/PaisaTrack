# PaisaTrack — Project Status Report

Reviewed 2026-07-08 by @codex, against PLAN.md, TASKS.md, README.md, docs/,
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

Phase 2 is partially built. Completed or prepared work includes:

- T-035/T-036: duplicate/counterparty ADR and schema v2 implementation.
- T-037: manual transaction entry, pending canonical toolchain verification.
- T-038: transaction detail/edit writes feedback rows, pending verification.
- T-039: seed-map categorization and rules engine, pending verification.
- T-040: isolated Decision policy v1 prep, not yet wired to ingest.
- T-041: category manager.
- T-042: settings v1 and local data reset.
- T-043: encrypted export/import.
- T-047: IndusInd NEFT/ACH-credit templates, fixture/SMS-dump coverage reported
  at **407/411 statement rows (99.03%)**, pending Flutter fixture tests and a
  fresh device export before Done.

## 2. Current build goal

Finish Phase 2 so the app is daily-usable:

1. Run the canonical `flutter analyze --no-pub` and
   `flutter test --no-pub --concurrency=1` verification pass for
   T-037/T-038/T-039 and T-047.
2. Wire Decision policy v1 into the ingest/status flow once T-039 clears.
3. Build T-044 ask-now notifications with top category guesses and feedback/rule
   writes.
4. Build T-045 weekly review for `needs_review` transactions.
5. Run T-046 Phase 2 exit review against the PLAN.md criteria.

## 3. Architecture summary

The app is local-first:

- Android native code filters and captures candidate SMS messages.
- Dart capture code parses messages through JSON template registries.
- `SmsIngestor` writes raw SMS and normalized transaction rows in encrypted
  SQLite, suppressing linked duplicates instead of deleting them.
- Enrichment currently applies user rules and a bundled seed category map.
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

- Several Phase 2 tasks have tests written but not executed in the canonical
  Flutter toolchain after recent changes.
- GitNexus reported the index 3 commits behind HEAD during this review; use the
  task board and worklog as fresher status until the index is refreshed.
- T-040 exists as isolated policy logic only; transaction status writes still
  need to be wired deliberately.
- Ask-now notifications and weekly review are the main missing user workflows
  before Phase 2 can exit.
- T-047's 99.03% coverage is from fixture/SMS-dump simulation; the final device
  export confirmation is still outstanding.

## 6. Bottom line

The project is no longer a foundation scaffold. It is a working local-first SMS
finance tracker moving through Phase 2. The next push should be verification
first, then decision-policy wiring, ask-now notifications, weekly review, and a
Phase 2 exit review.
