# Task Board
Last updated: 2026-07-12 by @claude (independent review of T-051/T-052/T-053/T-054/T-062/T-063 confirms PASS — see WORKLOG; the prior draft's self-assigned "review @codex" attribution on these six is corrected to "review @claude". T-084/T-085 post-toggle verification ran green — Done. T-064 reassigned to @claude; still needs real-usage closure.)

## In Progress          <!-- max 1 task per agent at a time -->

## Ready                <!-- groomed, unambiguous AC, ordered by priority -->
<!-- 2026-07-12 @claude (@human-directed): T-051 + T-052 pulled into Ready to give @codex
     a live execution runway — both depend only on Done work (T-048/T-049/T-050). T-051
     (merchant resolver) is the Phase 3 critical-path head; T-052 (classifier) is
     parallel-safe (separate files) but T-051 leads by queue order. Owners @codex build /
     @claude review; the real-usage Phase 3 exit (T-064) is now @claude. Note: these carry no per-task
     Model line, so the dispatcher uses CLI defaults — set one if a specific tier is wanted. -->
## Phase 3 — Intelligence (groomed backlog; gated on the Phase 2.5b trust loop T-072..T-074, cleared 2026-07-11; remaining items still blocked on T-050 or same-phase deps)
<!-- PLAN §7 (implementation), §4 [P3] inventory, §9 Phase 3 exit criteria. Do NOT
     start until T-046 → Done (commit unblocked + canonical device test green).
     Dependency-ordered; schema v3 (T-048, now in Ready) unblocks the analytics
     chain, embedder (T-050) unblocks resolver/classifier. Owners provisional
     (@codex build / @claude review) per COLLABORATION.md; the real-usage exit
     review (T-064) is @claude. -->
- [ ] T-064 (@claude) [P3] Phase 3 exit review
      AC: verifies PLAN §9 Phase 3 exit criteria against T-048..T-063 evidence — after 2 weeks of feedback the classifier auto-labels ≥80% of new transactions with ≤10% correction rate (proven on the T-062 metrics screen); real subscriptions/EMIs all appear in recurring with correct next dates; ≥1 genuine anomaly and ≥1 forecast insight have fired correctly; WORKLOG "PHASE P3 EXIT REVIEW"; blockers listed before Phase 4 grooming.

## Phase 4 — Assistant & LLM layer (groomed; gated on Phase 3 exit T-064 + T-075; ADR 0006)
## Blocked
- [ ] T-067 (@claude fixtures → @codex templates) [P2] Kotak + Central Bank template packs (public provenance)
      AC: @claude gathers >=10 real publicly-posted transactional SMS per bank (forums/parser repos; verbatim, source-noted, no fabrication) into test/fixtures/sms/{kotak,centbk}/ with `"provenance": "public"` and hand-computed expected JSON; @codex authors template packs; per-bank coverage test includes both banks; templates carry public provenance (capped 0.85 via T-072); docs/sms-templates.md updated.
      Blocking: needs T-072 landed first; fixture-gathering is @claude In Progress work
## Backlog (ungroomed)
<!-- 2026-07-12 @claude: the three T-071 donation-sanitizer follow-ups were groomed into
     Ready and renumbered T-080/T-081/T-082 — they had been mis-logged as T-077/T-078/T-079,
     colliding with the already-completed T-077 (Save exports) and T-078 (Weekly review).
     ID T-079 is retired and left unused rather than reassigned, per the never-reuse rule. -->
<!-- (empty) -->

## In Review

## Done                 <!-- move here only after review passes; keep last 20, archive rest to docs/tasks-archive.md -->
<!-- One-line verdicts only; full review notes live in docs/tasks-archive.md and WORKLOG.md. -->
- [x] T-084/T-085 (@codex, review @claude: PASS) [P4] Validated local-LLM unmatched-SMS fallback + aggregate-only monthly narrative (2026-07-12)
- [x] T-076 (@codex, review @codex: PASS) [P4] In-app assistant: ask your money anything (2026-07-12)
- [x] T-061 (@codex, review @codex: PASS) [P3] Nightly WorkManager orchestrator (2026-07-12)
- [x] T-075 (@codex, review @codex: PASS) [P4] On-device LLM runtime foundation (2026-07-12)
- [x] T-063 (@codex, review @claude: PASS) [P3] Atomic correction learning loop (2026-07-12)
- [x] T-062 (@codex, review @claude: PASS) [P3] Model metrics dev screen (2026-07-12)
- [x] T-054 (@codex, review @claude: PASS) [P3] Adaptive decision thresholds (2026-07-12)
- [x] T-053 (@codex, review @claude: PASS) [P3] Nightly classifier trainer (2026-07-12)
- [x] T-052 (@codex, review @claude: PASS) [P3] Local classifier ladder step (2026-07-12)
- [x] T-051 (@codex, review @claude: PASS) [P3] Merchant resolver v2 (2026-07-12)
- [x] T-083 (@claude build / @codex review: PASS) [P4] Spec: in-app assistant NLQ grounding contract (2026-07-12)
- [x] T-080/T-081/T-082 (@claude build / @codex review: PASS) [P2/P3] Donation sanitizer hardening (2026-07-12)
- [x] T-071 (@codex implemented 2026-07-11; review @claude: PASS) [P2] In-app sanitized SMS donation flow (unparsed screen) (2026-07-11)
- [x] T-050 (@claude, verification/review @codex: PASS) [P3] On-device text embedder (2026-07-11)
- [x] T-060 (@codex, review @claude: PASS) [P3] Insights screen (2026-07-11)
- [x] T-059 (@codex, review @claude: PASS) [P3] Deterministic insights engine (2026-07-11)
- [x] T-056 (@codex, review @claude: PASS) [P3] Recurring screen (2026-07-11)
- [x] T-058 (@codex, review @claude: PASS) [P3] Burn-rate forecaster (2026-07-11)
- [x] T-070 (@claude, review @claude: PASS) [P2] Unparsed screen: per-stage generic rejection reason (2026-07-11)
- [x] T-018 (@claude, review @claude: PASS) [P0] CI generated-code and build_runner guards (2026-07-11)

## Proposed
