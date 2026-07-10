# ADR 0004 — Automated agent handoff via post-commit dispatch

Status: accepted (@human directed, 2026-07-10)

## Context

COLLABORATION.md coordinates @claude and @codex entirely through repo files
(TASKS.md, WORKLOG.md), but had no push mechanism: each agent acted only when
the human manually told it to check the docs. Handoffs (implement → review →
next task) stalled on human prompting, causing friction and missed loops.
Both agents share the same working copy, and every protocol-compliant session
ends in a commit — so a commit is a complete, reliable "board changed" signal.

## Decision

A post-commit hook step (`scripts/agent_handoff.sh`) evaluates TASKS.md after
every commit and dispatches the agent with actionable work:

- **@claude** when `## In Review` has open items (review outranks new work).
- **@codex** when In Review is empty, no @codex task is In Progress, and an
  unchecked (@codex) task sits in `## Ready`.
- Neither → no-op. Serial by design: one active agent at a time.

Dispatch mechanics: @codex launches headless (`codex exec --full-auto`, logs
in `.handoff/logs/`). @claude launches via the Claude Code CLI when installed;
otherwise the hook drops `.handoff/claude.pending`, which a Cowork scheduled
task polls every 30 minutes. Dispatched sessions run fixed prompts
(`scripts/prompts/*_session.md`) that require the agent to re-verify the board
and exit without changes when nothing is actionable — the shell script stays
dumb; judgment stays in the agents.

Safety rails: `.handoff/paused` kill switch; per-target dedup on the TASKS.md
content hash; 10-minute per-target rate limit; PID lock against concurrent
runs of the same agent; auto-runs set `CODEX_SKIP_COMMIT_REVIEW=1` (the
handoff loop replaces per-commit review with task-level review); the hook
never blocks or fails a commit. `.handoff/` is gitignored (machine-local
state, never shared truth — TASKS.md remains the single source of truth).

## Consequences

- Handoffs fire within seconds of a commit (codex) or ≤30 min (claude via
  poll) with zero human prompting; the human remains merge authority and can
  pause the loop at any time (`touch .handoff/paused`).
- Agents now run and commit unattended: token cost is bounded by the rate
  limit + serial dispatch, and correctness by the unchanged review gate —
  nothing reaches Done without an independent @claude review.
- The board format in COLLABORATION.md §2 is now load-bearing for automation:
  section headers and `(@agent)` assignee tags must not be renamed without
  updating `agent_handoff.sh`.
- Human-triggered sessions are unaffected; the hook simply makes the existing
  protocol self-driving.
- Amendment 2026-07-10: the per-commit Codex review (T-033) is removed from
  the hook entirely (not just for auto-runs). Task-level @claude review is
  the quality gate; the per-commit pass was redundant, slow, and ran in the
  foreground — blocking the terminal and delaying commands queued behind the
  commit (observed blocking `handoff.sh resume`). Manual re-run remains
  available via `codex exec --sandbox read-only review --commit <sha>`.
- Amendment 2026-07-10 (operational hardening, details in COLLABORATION §7):
  (a) control CLI `scripts/handoff.sh {on|off|status|kick|resume}`; (b)
  failure latch — a dispatched run exiting non-zero auto-pauses the loop
  until a human runs `handoff.sh on`; (c) commit delegation — the codex
  sandbox keeps `.git` read-only, so codex writes `.handoff/commit-msg` and
  the unsandboxed wrapper commits on its behalf; (d) per-task model
  selection via an optional `Model: <name> [effort]` line in the task block,
  set at grooming and passed to `codex exec -m` / `model_reasoning_effort`.
