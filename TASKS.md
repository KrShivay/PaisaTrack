# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

<!-- Keep at most one implementation task here. -->

## Completed P0 Blockers

- [x] T-121 Make dashboard guidance truthful (period-gated guidance, no hardcoded state, budget input dialog).
- [x] T-122 Repair permission, startup, and key-loss recovery (openAppSettings, DatabaseErrorScreen with retry).
- [x] T-123 Make Sort persistence-safe (session skip tracking, DB-first update with SnackBar on error).
- [x] T-124 Complete local-data erasure and DB-key durability (clearAllNativeState channel, commit() for passphrase store, synchronized creation lock).
- [x] T-125 Establish production Android release lane (keystore.properties, Gradle release signing guard, release-signing.md docs).

## Ready

<!-- P1 tasks ready for next phase -->
- [ ] T-126 (@codex) [P1] Unify financial calendar and spending semantics.
      Module: dashboard repository, burn rate, anomalies, insights, ingestion.
      Depends: shared analytics-eligibility view/service and injected local
      calendar boundary service.
      Gap: dashboard uses local time and spending categories while intelligence
      uses UTC and broader debit/credit sets; ask quota resets at 05:30 IST.
      Next: define one predicate and boundary API, convert local ranges to query
      instants, and add parity tests across midnight/month boundaries.
- [ ] T-129 (@codex) [P1] Add durable capture retry and privacy-safe diagnostics.
      Module: SMS backfill/ingestion, Android filter, SMS lookup/dev diagnostics.
      Depends: versioned retry reason/state.
      Gap: failed/unparsed rows count as known, import is marked complete after
      row failures, and live errors/unknown senders are not durably measurable.
      Next: persist content-free reason codes and retry version, retry bounded
      failures after parser upgrades, and expose accepted/rejected/failed counts.
- [ ] T-108 (@codex) [P2] Measure and extend bank sender/template coverage.
      Module: Android SMS filter, template registry, developer diagnostics.
      Depends: T-129 content-free native rejection counters.
      Implemented: HDFC/ICICI deterministic templates, sender allowlist entries,
      and sanitized tests are complete.
      Gap: senders rejected natively are invisible to Dart, and additional banks
      require evidence-backed fixtures.
      Next: expose unknown-sender counts without bodies/identifiers, then add
      bank coverage only from sanitized fixtures with exact parser assertions.

### Scale, privacy, and maintainability

- [ ] T-127 (@codex) [P1] Stream and bound encrypted backup/import.
      Module: backup service, document gateway, privacy.
      Depends: vNext archive format.
      Gap: picker and backup hold full ciphertext/plaintext/table copies in
      memory; KDF input allows 256 MiB before authentication; raw SMS can live
      indefinitely in backups.
      Next: enforce file/row/ciphertext limits now, accept known KDF profiles,
      exclude expired/raw SMS, then design chunked authenticated streaming with
      progress and compatibility tests.
- [ ] T-115 (@codex) [P1] Profile startup, import, and model memory.
      Module: bootstrap, capture, LiteRT-LM.
      Depends: signed profile/release build and target device.
      Next: record cold start, 10k-message import, baseline/navigation/model PSS,
      native/GPU caches, and idle/background release evidence.
- [ ] T-117 (@codex) [P2] Move payee-label aggregation/search to SQL.
      Module: payee label repository/UI.
      Depends: paged identity query.
      Gap: UI search exists, but the repository watches and groups the complete
      transaction history in Dart.
      Next: add SQL aggregation, unresolved/search filters, paging, and duplicate
      suggestions with realistic-volume tests.
- [ ] T-118 (@codex) [P2] Explain recurring ineligibility.
      Module: recurring detector/repository/UI.
      Depends: structured eligibility reason model.
      Next: show per-merchant progress, cadence/amount gaps, and fragmented
      identity warnings rather than a bare empty state.
- [ ] T-130 (@codex) [P2] Reduce architectural coupling and numeric risk.
      Module: data/domain architecture.
      Depends: staged migrations.
      Gap: database↔duplicate-rule import cycle, oversized repository/screens,
      O(n²) owned-transfer reconciliation, and monetary `double`/SQLite REAL.
      Next: introduce domain DTOs, split reads/commands/corrections, replace
      transfer scan with indexed SQL, and plan integer-paise migration.

### Accessibility, security, and release

- [ ] T-125 (@codex) [P0] Establish a production Android release lane.
      Module: Gradle, CI, distribution.
      Depends: CI-managed signing or Play App Signing.
      Gap: release builds use the debug key; CI omits native tests.
      Next: fail release assembly without production signing, add Android app
      and Keystore tests plus debug/release assembly to CI, and document key
      rotation/rollback.
- [ ] T-128 (@codex) [P1] Complete accessibility and failure-state coverage.
      Module: shell and all primary Bloom screens.
      Depends: stable P0 flows.
      Gap: unlabeled gesture controls, missing selected semantics, sub-48dp
      targets, light-theme contrast failure, weak large-text/semantics tests,
      and several errors rendered as empty states.
      Next: use semantic Material controls, ≥48dp targets, corrected tokens,
      1.5×/2× and multi-viewport widget tests, then TalkBack acceptance.
- [ ] T-090 (@codex) [P4] App lock.
      Module: app lifecycle/security.
      Depends: T-122/T-124 recovery contracts.
      Next: design launch/resume lock with unavailable-biometric and recovery
      paths that do not weaken SQLCipher.
- [ ] T-091 (@codex) [P4] Privacy-safe home widget.
      Module: Android widget.
      Depends: T-090.
      Next: define locked/unlocked disclosure and a configurable aggregate-only
      surface.
- [ ] T-094 (@codex) [P5] Distribution and portfolio release package.
      Module: release/product.
      Depends: T-090, T-115, T-125, T-128.
      Next: signed release, SMS-permission declaration or maintained sideload
      path, screenshots, privacy/architecture story, rollback checklist.

### Planned product outcomes

- [ ] T-102 (@codex) [P2] Local statement import and reconciliation.
      Module: new statement import/reconciliation module.
      Depends: source fingerprint and reconciliation schema.
      Next: specify CSV preview, account mapping, idempotency, guarded matching,
      ambiguity review, and transactional rollback.
- [ ] T-100 (@codex) [P2] Reimbursement, refund, and reversal tracking.
      Module: transaction relationships and analytics.
      Depends: shared net-spending contract from T-126.
      Next: design additive full/partial/many-link schema and explained net
      totals without mutating source transactions.
- [ ] T-101 (@codex) [P3] Recurring calendar and future-message detection.
      Module: capture and expected-event/recurring domain.
      Depends: expected events stored separately from settled transactions.
      Next: design reminder deduplication, debit settlement matching, snooze,
      cancel, missed, and price-change states.
- [ ] T-098 (@codex) [P3] Monthly category budgets.
      Module: dedicated budget schema/repository/UI.
      Depends: T-100 and T-126.
      Gap: the current overall monthly budget/merchant-cap prototype is not this
      feature and uses `baselines`.
      Next: design per-category/per-month limits, net refund/reimbursement
      semantics, remaining/threshold/projection state, and migration away from
      prototype storage.
- [ ] T-096 (@codex) [P3] Tolerant free-text category resolution.
      Module: assistant/category identity.
      Depends: stable category aliases.
      Next: add typo-tolerant matching that refuses ambiguity.

### Planned rework — task briefs in `docs/tasks/`

Full detail lives in one brief per parent ticket. Read `TASKS.md` to pick a task,
then `docs/tasks/T-NNN.md` for **only the sub-task you claimed** — typically
60–110 lines. Do not read the design documents unless a brief points you at a
section. See `docs/tasks/README.md` for the format.

Sub-task ids suffix the parent (`T-146a`). Parent ids are containers and are
never worked directly. Sizes: `~S` under half a day, `~M` up to a day, `~L` split
further before claiming.

#### SMS intelligence — `docs/sms-intelligence-design.md`

Phase A blocks B; B blocks C and D.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-131a** | P0 | ~M | Add `FieldEvidence` to the record contract | — |
| **T-131b** | P0 | ~M | `SpanVerifier`; deterministic parsers emit evidence | T-131a |
| **T-131c** | P0 | ~M | `LlmFieldLocator` replaces `LlmExtractor` | T-131b |
| **T-132a** | P0 | ~M | Schema v8: `lifecycle_state`, `message_kind` | T-131a |
| **T-132b** | P0 | ~M | Message-kind classifier + locale cue pack | T-132a |
| **T-132c** | P0 | ~M | Route kinds through ingestion; narrow `_hardReject` | T-132b |
| **T-143a** | P1 | ~S | `feature_flags` table | — |
| **T-143b** | P1 | ~M | Link-sequence and adversarial fixtures | — |
| **T-143c** | P1 | ~L | Shadow mode and on-device metrics | T-143a/b |
| **T-133a** | P1 | ~L | Shape scoring and quarantine store | T-129, T-132b |
| **T-133b** | P1 | ~M | "Messages we couldn't read" + retry on upgrade | T-133a |
| **T-134a** | P1 | ~M | `financial_events` + `transaction_links` schema | T-132a |
| **T-134b** | P1 | ~L | Correlation key ladder; drop substring matching | T-134a, T-143b |
| **T-134c** | P1 | ~M | Materialized dedup/transfer projections | T-134b |
| **T-135a** | P1 | ~L | `net_amount` as the single aggregate input | T-134a, T-126 |
| **T-135b** | P1 | ~M | Refund linking (auto ≥0.90, else ranked review) | T-135a |
| **T-135c** | P1 | ~M | Cash, transfers, card-bill treatment | T-135a |
| **T-136a** | P1 | ~L | Counterparties table + identity parser | T-134a |
| **T-136b** | P1 | ~M | Person/merchant split; people bypass the ladder | T-136a |
| **T-136c** | P1 | ~M | Previewed, reversible identity backfill | T-136b |
| **T-137a** | P2 | ~M | Nightly merchant clustering (suggestions only) | T-136b |
| **T-137b** | P2 | ~M | Cluster review and one-tap merge | T-137a |
| **T-138a** | P2 | ~M | `expected_events` schema + dedup key | T-132a |
| **T-138b** | P2 | ~M | Reminders and mandates become expected events | T-138a, T-132c |
| **T-138c** | P2 | ~M | Fulfilment, snooze, cancel, missed | T-138b, T-134b |
| **T-139a** | P2 | ~M | Classify subscription vs EMI vs variable bill | T-136b, T-138b |
| **T-139b** | P3 | ~S | Price-change insight | T-139a |
| **T-140a** | P2 | ~M | Merchant-memory step in the categorizer | T-136b, T-143a |
| **T-140b** | P2 | ~M | Classifier feature upgrade | T-140a |
| **T-140c** | P2 | ~S | LLM category suggestion capped at 0.70 | T-140b, T-131c |
| **T-141a** | P3 | ~S | Anomaly: series suppression + amount floor | T-139a |
| **T-142a** | P3 | ~M | Highlight evidence spans in the source message | T-131a, T-147a |
| **T-144a** | P1 | ~S | Manifest scope + merged-manifest CI guard | — |
| **T-144b** | P1 | ~M | Prominent disclosure + capture controls | T-133a |

Closes on completion: T-100 (by T-134/T-135), T-101 (by T-132/T-138).

#### UI gaps — `docs/ui-gaps-and-redesign.md`

T-152a unblocks four screens. T-150a precedes the Ask rebuild. T-153a precedes
T-154a.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-146a** | P1 | ~S | Pass and resolve the category icon (8 call sites) | — |
| **T-146b** | P2 | ~S | Fix the recurring screen's category id | — |
| **T-148a** | P1 | ~S | Whole category row becomes the ≥48dp control | — |
| **T-148b** | P2 | ~M | Inline category chips in the detail sheet | T-148a, T-145a |
| **T-152a** | P2 | ~M | `showBloomFullScreenSheet` | — |
| **T-145a** | P2 | ~M | Category picker to the full-screen route | T-152a |
| **T-145b** | P3 | ~S | Sticky search, section headers, result count | T-145a |
| **T-147a** | P2 | ~M | Render the source message + retention degradation | T-152a |
| **T-147b** | P3 | ~S | Provenance badge and privacy gating | T-147a |
| **T-150a** | P2 | ~M | Extract prompt catalogue; test against validator | — |
| **T-150b** | P2 | ~M | Searchable, grouped empty state | T-150a |
| **T-150c** | P3 | ~S | Rotating composer chips | T-150a, T-151c |
| **T-151a** | P2 | ~M | Sheet presentation; remove the duplicate title | T-152a |
| **T-151b** | P2 | ~S | Bubble geometry and verdict answers | T-151a |
| **T-151c** | P2 | ~S | Composer styling | T-151a |
| **T-151d** | P2 | ~M | Thinking, model-missing, no-answer states | T-151b |
| **T-151e** | P3 | ~M | Inline charts and follow-up chips | T-151b |
| **T-153a** | P2 | ~M | Ordered queue + cursor replaces the skip filter | — |
| **T-153b** | P2 | ~S | Back navigation through seen cards | T-153a |
| **T-153c** | P2 | ~M | Skipped end state, persistence, progress | T-153a |
| **T-154a** | P2 | ~M | Open transaction detail from the Sort card | T-153a, T-152a |
| **T-154b** | P2 | ~M | Inline corrections + guess refresh before Keep | T-154a |
| **T-149a** | P3 | ~M | Profile shell and personalisation | T-152a |
| **T-149b** | P3 | ~M | Habits and money shape | T-149a |
| **T-149c** | P3 | ~S | Data footprint and privacy posture | T-149a |

#### Suggested order

Ship first (small, independent, high visibility): T-146a, T-148a, T-131a.
Then the foundations everything else waits on: T-152a, T-143a/b, T-131b/c,
T-132a-c.

## In Review

<!-- Temporary: unresolved verification/review only. -->

## Board rules

- Keep exactly one instance of every `##` workflow heading; handoff automation
  parses them literally.
- Keep only unfinished work. Remove an item after implementation and required
  verification are complete.
- Move at most one implementation task to `In Progress`.
- `In Review` is temporary and contains only unresolved verification/review.
- Record current state in `docs/product-status.md`, durable decisions in ADRs,
  and completed evidence in Git history or `docs/archive/`.
