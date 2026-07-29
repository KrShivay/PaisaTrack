# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

<!-- Keep at most one implementation task here. -->

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
| **T-143a** | P1 | ~S | `feature_flags` table | — |
| **T-143b** | P1 | ~M | Link-sequence and adversarial fixtures | — |
| **T-143c** | P1 | ~L | Shadow mode and on-device metrics | T-143a/b |
| **T-133a** | P1 | ~L | Shape scoring and quarantine store | T-129 |
| **T-133b** | P1 | ~M | "Messages we couldn't read" + retry on upgrade | T-133a |

Completed work is retained in Git history: T-131a–c, T-132a–c, T-134a–c,
T-135a–c, T-136a–c, T-137a–b, T-138a–c, T-139a–b, T-140a–c, T-141a,
T-142a, and T-144a–b.

#### UI gaps — `docs/ui-gaps-and-redesign.md`

T-152a unblocks four screens. T-150a precedes the Ask rebuild. T-153a precedes
T-154a.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-150a** | P2 | ~M | Extract prompt catalogue; test against validator | — |
| **T-150b** | P2 | ~M | Searchable, grouped empty state | T-150a |
| **T-150c** | P3 | ~S | Rotating composer chips | T-150a, T-151c |
| **T-151a** | P2 | ~M | Sheet presentation; remove the duplicate title | — |
| **T-151b** | P2 | ~S | Bubble geometry and verdict answers | T-151a |
| **T-151c** | P2 | ~S | Composer styling | T-151a |
| **T-151d** | P2 | ~M | Thinking, model-missing, no-answer states | T-151b |
| **T-151e** | P3 | ~M | Inline charts and follow-up chips | T-151b |
| **T-153a** | P2 | ~M | Ordered queue + cursor replaces the skip filter | — |
| **T-153b** | P2 | ~S | Back navigation through seen cards | T-153a |
| **T-153c** | P2 | ~M | Skipped end state, persistence, progress | T-153a |
| **T-154a** | P2 | ~M | Open transaction detail from the Sort card | T-153a |
| **T-154b** | P2 | ~M | Inline corrections + guess refresh before Keep | T-154a |
| **T-149a** | P3 | ~M | Profile shell and personalisation | — |
| **T-149b** | P3 | ~M | Habits and money shape | T-149a |
| **T-149c** | P3 | ~S | Data footprint and privacy posture | T-149a |

T-145a, T-145b, T-146a, T-146b, T-147a, T-147b, T-148a, T-148b, and T-152a are
implemented on `main` (see WORKLOG.md) and removed from this board per the
board rules below.

#### Suggested order

Ship first (small, independent, high visibility): T-150a.
Then the foundations everything else waits on: T-143a/b, T-131b/c, T-132a-c.

#### Flutter refactor, no behavior change — `docs/tasks/`

Scoped to duplicated category/icon/color resolution, sheet/dialog APIs,
scattered threshold constants, the oversized `transaction_detail_screen.dart`,
Riverpod boundary violations, and shallow render-only tests. Narrows T-130's
"oversized repository/screens" gap for these specific files; does not replace
T-130's data-layer/DTO scope. T-159a (regression tests) should land before
T-157b starts — it is the safety net for the riskiest extraction here.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-156b** | P2 | ~M | Route 4 bespoke sheet presenters through Bloom helpers | — |
| **T-156c** | P2 | ~M | Standardize TransactionDetailScreen's presentation | T-158c |
| **T-157a** | P2 | ~M | Move raw Drift writes out of recurring/insights screens | — |
| **T-157b** | P2 | ~L | Shared category-correction + undo controller | T-159a |
| **T-157c** | P3 | ~S | Relocate `suggestedCategoriesProvider` out of the screen | — |
| **T-158a** | P2 | ~M | Extract pure functions (chip ranking, exclusion, evidence) | — |
| **T-158b** | P2 | ~M | Extract `TransactionDetailController` | T-157b |
| **T-158c** | P2 | ~M | Extract sub-widgets into `detail/` | T-158a |
| **T-158d** | P3 | ~S | Verify exclusion-reason parity (UI vs. analytics SQL) | T-158a |
| **T-159a** | P1 | ~M | Characterize correction/undo behavior before extraction | — |
| **T-159b** | P2 | ~S | Unit tests for extracted pure functions | T-158a |
| **T-159c** | P3 | ~M | Convert remaining shallow render tests to behavioral | T-158c |

Suggested order: T-159a first (safety net) — then T-155/T-156/T-157a/T-158a
can proceed in any order (independent) — then T-157b — then T-158b/c — then
T-156c and T-159b/c last.

## In Review

- [ ] T-156a (@codex) [P2] Shared Bloom dialog helper.
      Implementation: `showBloomDialog` now owns shared Bloom chrome and all
      direct dialog calls route through it. Verification remaining: add the
      per-screen action-behavior tests required by `docs/tasks/T-156.md` and
      clear the repository analyzer findings before approval.

## Backlog

<!-- Groom future work here before promoting it to Ready. -->

## Board rules

- Keep exactly one instance of every `##` workflow heading; handoff automation
  parses them literally.
- Keep only unfinished work. Remove an item after implementation and required
  verification are complete.
- Move at most one implementation task to `In Progress`.
- `In Review` is temporary and contains only unresolved verification/review.
- Record current state in `docs/product-status.md`, durable decisions in ADRs,
  and completed evidence in Git history or `docs/archive/`.
