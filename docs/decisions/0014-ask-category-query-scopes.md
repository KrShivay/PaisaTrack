# ADR 0014: Ground Ask category queries in taxonomy scopes

- Status: Accepted
- Date: 2026-09-27

## Context

Ask previously resolved category filters from display names alone and matched a
transaction's exact category ID. That made broad parent queries miss spending
stored in child categories, while shared words could fall through to merchant
lookup and produce a misleading empty total. The query engine also omitted the
dashboard's settled-state and spending-category eligibility.

## Decision

Local category matches carry stable category IDs. A selected parent includes
its descendants; an exact child remains scoped to that child and its own
descendants. Multiple explicit category scopes are queried as a deduplicated
union. The model-facing compact intent may return multiple canonical category
names, but validation rejects unknown, duplicate-name, or malformed category
filters. Unrelated ambiguity is refused before merchant fallback. Amounts
remain calculated from SQL results, and spending totals use the dashboard's
settled, non-excluded spending-category rules.

## Consequences

`food` can answer across the seeded Food & Dining subtree; `food delivery`
remains narrow; and `food delivery and groceries` includes both requested
scopes. Generic ambiguity across unrelated categories is a refusal, not an
unfiltered or merchant query. Fuzzy typo matching remains a separate feature.

No database schema, migration, transaction retention, or network behavior
changes.
