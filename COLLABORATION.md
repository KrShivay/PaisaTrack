# Collaboration Workflow

## Sources of truth

- `TASKS.md`: unfinished implementation work only.
- `PLAN.md`: future feature contracts and delivery order.
- `WORKLOG.md`: rolling handoff containing at most the latest three entries.
- `docs/architecture.md`, `docs/schema.md`, and `docs/privacy.md`: current
  technical constraints.
- `docs/decisions/`: durable decisions that should survive task completion.
- Git history: completed tasks, review evidence, and old plans.

Do not recreate a Markdown task archive or append unbounded session history.

## Required task-board headings

Keep these headings because `scripts/agent_handoff.sh` parses them:

```text
## In Progress
## Ready
## In Review
## Backlog
```

Only `Ready` and `In Progress` drive implementation. `In Review` is temporary;
after review passes, remove the task from the board. Do not maintain a `Done`
section.

## Task lifecycle

1. Groom one backlog task with acceptance criteria and dependencies.
2. Promote it to `Ready`.
3. The implementer moves it to `In Progress`.
4. Run GitNexus impact analysis before editing symbols.
5. Implement code, tests, and documentation.
6. Move it to `In Review` with concise verification evidence.
7. Independent review either returns it to `In Progress` or removes it after
   passing. Git history preserves the result.

## Definition of done

- Acceptance criteria are met and proven by non-vacuous tests.
- Privacy and local-first constraints remain intact.
- Schema changes include generated code and migration tests.
- `flutter analyze --no-pub`, focused tests, full Flutter tests, and
  `git diff --check` pass.
- Native changes also pass Android tests/compilation.
- `detect_changes()` shows only expected symbols and flows.
- Device-dependent behavior has recorded device evidence.
- Relevant architecture, schema, privacy, or manual-QA docs are updated.

## Session protocol

1. Read `TASKS.md`, `PLAN.md`, and the current `WORKLOG.md`.
2. Check the working tree and preserve unrelated user changes.
3. Re-verify task dependencies and acceptance criteria.
4. Work on one task only.
5. Update the task and replace/append the rolling handoff as needed.
6. Commit and push only when explicitly requested or when the active automation
   workflow authorizes it.

Any material privacy, dependency, schema, or architecture decision requires a
short ADR before implementation.
