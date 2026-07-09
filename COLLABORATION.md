# COLLABORATION.md — Two-Agent Working Protocol (Claude + Codex)

This repository is developed by two AI agents and one human. All coordination happens **through files in the repo** — never assume the other agent saw a chat message. If it isn't in git, it didn't happen.

## 1. Roles

| Actor | Role | Owns |
|---|---|---|
| **@codex** | Implementation engineer | Writing code + tests for assigned tasks, keeping CI green |
| **@claude** | Architect & reviewer | Task breakdown, design decisions, code review, plan updates, writing specs for tricky modules (intelligence layer especially) |
| **@human** (Prateek) | Product owner & tiebreaker | Supplies SMS fixtures, approves ADRs, resolves `## Blocked`, tests on real device, final merge authority |

Either agent MAY flag problems anywhere, but only the owner changes it. Codex does not restructure the plan; Claude does not push unreviewed implementation to main. Disagreements between agents become a `## Blocked` task for @human with both positions stated in ≤5 lines each.

## 2. The coordination files (repo root)

### TASKS.md — the single task board
Exact format (parsers on both sides depend on it):

```markdown
# Task Board
Last updated: 2026-07-05 by @claude

## In Progress          <!-- max 1 task per agent at a time -->
- [ ] T-012 (@codex) [P1] Template engine: matcher + registry loader
      AC: loads assets/templates/*.json; sender-ID match; fixture tests for HDFC pass
      Depends: T-006

## Ready                <!-- groomed, unambiguous AC, ordered by priority -->
- [ ] T-013 (@codex) [P1] Field normalizer: amounts (lakh commas), dates, account hints
      AC: unit tests cover cases in plan §10
- [ ] T-014 (@claude) [P1] Review spec: dedup strategy for paired bank+wallet SMS
      AC: docs/decisions/0003-dedup.md drafted

## Blocked
- [ ] T-007 (@human) NEED FIXTURES: HDFC + SBI, 30+ sanitized real SMS each
      Blocking: T-012, T-013

## In Review
- [ ] T-004 (@codex → review @claude) Schema v1 + migrations
      Evidence: test/data/db/migration_test.dart green in CI run #14

## Done                 <!-- move here only after review passes; keep last 20, archive rest to docs/tasks-archive.md -->
- [x] T-001 Flutter scaffold (2026-07-05)
```

Rules:
- Task IDs are global, sequential, never reused. Every commit message starts with `[T-xxx]`.
- Every task has: assignee, phase tag `[P0..P5]`, acceptance criteria (AC) that a test can verify, and dependencies if any.
- **WIP limit: one In-Progress task per agent.** Finish or block before picking the next.
- Only @claude (or @human) adds tasks to `## Ready`; @codex may propose tasks by adding them under `## Proposed` for Claude to groom.
- Anyone may move a task to `## Blocked`, and must state the specific question/need.

### WORKLOG.md — append-only session journal
Every agent session appends one entry. Newest at top.

```markdown
## 2026-07-05 21:40 @codex — T-012
- Did: template_matcher.dart + registry loader; 14 fixture tests green
- Files: lib/capture/template_engine/*, test/capture/template_engine/*
- Evidence: CI run #15 green; `flutter test` 47/47
- Decisions: regex compiled once at load, cached per sender — perf note in code
- Open questions: none
- Next: T-013
```

This is how each agent gets the other's context without sharing a chat session. Read the last 3 entries at session start, always.

### docs/decisions/ — ADRs
Any deviation from PAISA_TRACK_PLAN.md, any new dependency of consequence, any schema change: short ADR (`NNNN-title.md`: Context / Decision / Consequences, ≤1 page). ADRs touching the frozen record contract (plan §6.2) or privacy rules (plan §8) require explicit @human approval noted in the ADR before implementation.

## 3. Workflow

```
@claude grooms plan → tasks in Ready (with AC)
@codex pulls top Ready task → In Progress → implements + tests → In Review + WORKLOG entry
@claude reviews (see §4) → pass: Done | fail: back to In Progress with review notes in the task
@human: merges to main, supplies fixtures, approves ADRs, device-tests phase exits
```

Branching: trunk-based. Branch `T-xxx-short-name` per task, PR to `main`, squash merge. CI must be green to merge. Small tasks (<~300 LOC) preferred — Claude splits anything bigger during grooming.

Phase gates: when all tasks of a phase are Done, @claude verifies the phase exit criteria (plan §9) against actual tests, writes a `WORKLOG` entry titled `PHASE Px EXIT REVIEW`, and only then grooms the next phase into Ready. @human confirms on a real device for P1, P2, P3 exits.

Definition of Done: every feature must include matching tests, code documentation, and project documentation in the same change. Tests must prove the behavior or contract added by the feature. Code documentation must cover public APIs and non-obvious domain logic with Dart `///` comments. Project documentation must update the relevant project doc, ADR, schema/privacy note, README, or manual verification notes. If automated tests or docs are intentionally not added, the task and `WORKLOG.md` entry must state why. See `docs/development.md`.

## 4. Review checklist (@claude, every In Review task)
1. AC met, proven by tests (run them / read CI evidence — don't trust the summary)
2. Tests actually assert behavior (no vacuous tests); fixtures added for any new SMS variant
3. Code documentation and project documentation updated for the feature, or a clear reason recorded in the task and `WORKLOG.md`
4. Plan conformance: folder placement, enricher interface, constants not inlined, flags respected
5. Privacy rules: no raw SMS in logs/payloads; anonymizer path if network involved
6. Frozen contract untouched (or ADR present + approved)
7. WORKLOG entry complete
Review outcome goes into the task item as `Review: PASS` or `Review: CHANGES — <numbered list>`.

## 5. Conflict avoidance
- File-level ownership follows the task: while T-xxx is In Progress, its listed target files are locked to that agent. Claude grooms tasks so file sets don't overlap between concurrently-open tasks.
- `TASKS.md`/`WORKLOG.md` conflicts: append-only discipline (new entries on top for WORKLOG, in-place moves for TASKS) + always `git pull` at session start makes conflicts rare; if one occurs, keep both entries, fix ordering.
- Never force-push. Never rewrite the other agent's WORKLOG entries.

## 6. Session-start ritual (both agents, verbatim)
1. `git pull`
2. Read TASKS.md fully; read last 3 WORKLOG entries; read any new ADRs since your last session
3. State (in your reply to the human): current phase, your task, blockers you see
4. Work. 5. Update TASKS.md + append WORKLOG. 6. Commit + push. A session that ends without a WORKLOG entry is an incomplete session.

## 7. Automated handoff (ADR 0004)

Commits are the handoff signal. `.githooks/post-commit` runs
`scripts/agent_handoff.sh` after every commit: it reads TASKS.md and
dispatches @claude when `## In Review` has open items, or @codex when In
Review is empty, no @codex task is In Progress, and a `(@codex)` task sits in
Ready. Dispatched sessions use the fixed prompts in `scripts/prompts/` and
MUST re-verify the board themselves, exiting with no changes when nothing is
actionable. One active agent at a time; review outranks new work.

Operational notes:
- Pause everything: `touch .handoff/paused` (remove to resume).
- Logs: `.handoff/logs/`; state/locks live in `.handoff/` (gitignored).
- @claude fallback: without the `claude` CLI, the hook drops
  `.handoff/claude.pending` and a Cowork scheduled task polls it (~30 min).
- Auto-runs skip per-commit Codex review (task-level review replaces it).
- The §2 board format is load-bearing for this automation: do not rename
  section headers or `(@agent)` tags without updating `agent_handoff.sh`.
- @human remains merge/override authority; manual sessions work unchanged.
