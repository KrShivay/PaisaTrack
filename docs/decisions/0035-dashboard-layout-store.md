# ADR 0035 — Dashboard layout and interaction-count store (schema v22)

Status: Proposed (T-207; planning only, 2026-10-10). Depends on ADR 0034
having claimed schema v21.
Schema version numbers here are provisional; see the allocation rule in
[schema](../schema.md#planned-additive-areas).

## Context

The dashboard is a fixed column of widgets
(`lib/features/dashboard/dashboard_screen.dart`). The owner wants pin/hide/
reorder, "save Ask answer as card", and an order learned from the user's own
usage, all local (ADR 0002).

## Decision

1. Two additive tables in schema v22 (not `feature_flags`, which is a scalar
   key/value store with typed flags, `feature_flags_table.dart`; layout needs
   ordered rows, per-row backup and a typed query spec):
   - `dashboard_cards(id PK, card_type, config_json, position int,
     pinned bool, hidden bool, origin 'builtin'|'saved_ask', created_at,
     updated_at)`. `config_json` for `saved_ask` holds only a validated typed
     intent spec (`AssistantIntent` wire form) and a title; never an answer,
     number or SMS text. Builtin cards are rows created lazily from a Dart
     registry; unknown `card_type` rows are ignored (forward compatible).
   - `dashboard_card_stats(card_id, day int, opens int, taps int, PK card_id+day)`
     — per-day counters only, pruned to 60 days; no timestamps of individual
     events, no content.
2. Ranking is deterministic and local: pinned first (user order), then
   `score = decayed(taps*3 + opens) + urgency(due soon, anomaly, low balance)`;
   hidden never shown; reorder by user sets `position` and freezes auto
   ranking for that card group. No model, no embedding, no export.
3. Stats are never part of backup (regenerable); layout rows are. Both are
   wiped by delete-everything.
4. UI reads layout from a single cached provider; first frame renders the last
   persisted layout (or built-in default) so reorder never causes flicker.

## Consequences

- Rollback: flag `dashboard_custom_layout` off renders the built-in static
  order; tables are ignored.
- Saved cards re-run the deterministic query on render (cached by input
  hash); they cannot drift from the validated query engine.
