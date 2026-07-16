# Current Handoff

This is a rolling handoff, not an append-only project history. Keep only the
latest three development entries; Git history retains older evidence.

## 2026-07-16 — Independent code review of the full application (@claude)

- Reviewed all of lib/ and the Android capture/keystore code. Core verdict:
  architecture, privacy handling, and test discipline are sound; defects are
  concentrated in the new incremental catch-up, decision policy, and unbounded
  query patterns.
- Filed groomed fixes as T-105..T-110 in `TASKS.md`. T-104 device QA now
  depends on T-105 (catch-up StateError on empty/single-page inboxes,
  dead-process SMS drop); T-103 depends on T-107 (bounded queries).
- Deleted `PROJECT_STATUS_REPORT.md` (unreferenced; duplicated README and
  TASKS.md content).

## 2026-07-16 — T-105, T-106, and T-107 correctness/scale fixes

- Incremental catch-up now handles null terminal cursors and scans a bounded
  overlap beyond the first known SMS to recover recent live-ingest gaps.
- Seen VPA counterparties can auto-classify through the normal confidence
  policy; unseen VPAs still fail closed, and generic parsing no longer extracts
  ordinary email addresses as VPAs.
- Imports commit once per inbox page; known-id reads select identifiers only;
  ask/familiarity counts and dashboard aggregates run in SQL; transaction feeds
  page in 100-row increments with a six-row dashboard query.

## 2026-07-16 — T-095, T-097, T-099, T-103, and T-104 implementation

- T-095: reset now closes the current database, tolerates provider-open failure,
  removes DB/key/settings/import state, and recreates cleanly without Drift's
  duplicate-database warning.
- T-097: added canonical payee labels over merchant/VPA aliases, affected-history
  preview, preserved raw evidence, conflict refusal, Settings management, and
  labeled transaction display.
- T-099: added masked payment-source management, owned-source transfer pairing,
  analytics exclusion, migration/backfill, Settings UI, and backup v2 support
  with v1 compatibility.
- T-103/T-104: app shell now paints before deferred startup work; imports yield
  between rows; live EventChannel ingestion remains active; open/resume performs
  newest-first incremental catch-up without a full rescan.
- Fixed the hand-built v1 migration fixture so every additive migration reaches
  schema v5 while preserving the v1→v2 duplicate-link assertions.
- Remaining acceptance: validate startup responsiveness and real live/resume SMS
  delivery on a physical Android device.

## Verification (2026-07-16)

- `flutter analyze --no-pub`: clean.
- Full Flutter suite: 357/357 passed; focused T-105..T-107 suite: 52/52 passed.
- `git diff --check` and project-local Markdown links: clean.
- GitNexus full rebuild: 4,623 nodes, 10,045 edges, 231 flows.
- `detect_changes(scope: all)`: critical breadth across 334 symbols, 49 files,
  and 23 flows. This includes the earlier schema/startup/identity work plus the
  reviewed capture, transaction-feed, and dashboard paths covered by the suite.

## Next action

Run T-103/T-104 physical-device acceptance. T-108 is the next code task while
device evidence is unavailable, followed by T-102.
