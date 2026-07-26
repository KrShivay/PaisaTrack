# Task briefs

One file per parent ticket. Each file holds 1–5 **sub-tasks**, each sized as a
single mergeable change with its own tests.

## Why this layout

An agent picking up work should load its own task and nothing else. Before this
split, starting any ticket meant reading `TASKS.md` (~450 lines) to find it, then
`docs/sms-intelligence-design.md` (1,062) or `docs/ui-gaps-and-redesign.md` (427)
for the detail — roughly 1,500 lines of context before the first edit.

A brief here is self-contained: exact files, exact symbols, the change, the
tests, and acceptance criteria. Typical load is 60–110 lines.

## Reading protocol

1. `TASKS.md` — one line per task, pick one.
2. `docs/tasks/T-NNN.md` — read only the sub-task you claimed.
3. The files it names.

**Do not read the design documents unless a brief's `Rationale` line points you
at a specific section.** They exist to justify decisions already made in the
briefs, not to be re-derived per task.

## Brief format

```
### T-NNNx — <imperative title>          [P?] [~size]
Files:    paths, with line numbers where the defect is known
Depends:  task ids, or "none"
Change:   what to do, concretely
Tests:    what must be added or must pass
AC:       observable, checkable outcome
Rationale: doc §section — only when the "why" is non-obvious
```

## Conventions

- Sub-task ids suffix the parent: `T-146a`, `T-146b`. Parent ids are never
  worked directly; they are containers.
- Sizes: `~S` under half a day, `~M` up to a day, `~L` more than a day. Anything
  reaching `~L` should be split further before it is claimed.
- A sub-task that touches schema owns its migration **and** its migration test.
- Per `CLAUDE.md`: run `impact` before editing any symbol, and `detect_changes()`
  before committing. Briefs name symbols so `impact` can be run without a search.
- Definition of done for every sub-task: `flutter analyze`, focused tests, full
  Flutter tests, Android tests when native code changes, `git diff --check`,
  `detect_changes()`, and doc updates where behaviour or schema moved.

## Index

| Parent | Area | Sub-tasks | Brief |
|---|---|---|---|
| T-131 | Numeric trust boundary | 3 | [T-131.md](T-131.md) |
| T-132 | Lifecycle state split | 3 | [T-132.md](T-132.md) |
| T-133 | Admission and quarantine | 2 | [T-133.md](T-133.md) |
| T-134 | Events and link graph | 3 | [T-134.md](T-134.md) |
| T-135 | Net-spending contract | 3 | [T-135.md](T-135.md) |
| T-136 | Counterparty identity | 3 | [T-136.md](T-136.md) |
| T-137 | Merchant clustering | 2 | [T-137.md](T-137.md) |
| T-138 | Expected events | 3 | [T-138.md](T-138.md) |
| T-139 | Subscriptions and EMIs | 2 | [T-139.md](T-139.md) |
| T-140 | Categorization ladder | 3 | [T-140.md](T-140.md) |
| T-141 | Anomaly precision | 1 | [T-141.md](T-141.md) |
| T-142 | Explain this charge | 1 | [T-142.md](T-142.md) |
| T-143 | Corpus, shadow, metrics | 3 | [T-143.md](T-143.md) |
| T-144 | Play declaration and consent | 2 | [T-144.md](T-144.md) |
| T-145 | Category picker full screen | 2 | [T-145.md](T-145.md) |
| T-146 | Category icons | 2 | [T-146.md](T-146.md) |
| T-147 | Source message view | 2 | [T-147.md](T-147.md) |
| T-148 | Category row tap target | 2 | [T-148.md](T-148.md) |
| T-149 | Local profile | 3 | [T-149.md](T-149.md) |
| T-150 | Assistant prompt catalogue | 3 | [T-150.md](T-150.md) |
| T-151 | Ask design conformance | 5 | [T-151.md](T-151.md) |
| T-152 | Full-screen sheet route | 1 | [T-152.md](T-152.md) |
| T-153 | Sort cursor and skip | 3 | [T-153.md](T-153.md) |
| T-154 | Edit from Sort | 2 | [T-154.md](T-154.md) |
