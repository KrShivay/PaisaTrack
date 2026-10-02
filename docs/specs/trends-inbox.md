# Trends notification inbox lifecycle

The Trends inbox is a local presentation of valid, fresh T-178a insight claims.
It does not introduce new evidence, prose, or system notifications. Each item
renders through `ClaimRenderer`; raw SMS content is never read or persisted by
the inbox.

## Identity and creation

An item is created only when `ClaimValidator` accepts a claim and
`freshClaims` confirms its current evidence digest for the selected financial
calendar. Its stable key is the claim kind, canonical claim scope, and the
claim's calendar period. Scope values that represent sets are sorted before
encoding. A later period therefore creates a different item.

On first creation the state is `new`. Recomputing the same kind, scope, and
period updates its latest claim snapshot and metrics without changing its
state. Repeated threshold crossings within that identity do not create copies.

## State transitions

- `new` remains `new` throughout a Trends visit. It becomes `seen` once when
  the user leaves the Trends tab, pops away from the Trends route, or backgrounds
  the app. Opening an item does not clear its New marker during that visit.
- `seen` can be moved to `moved` with “Move to later”. `moved` can return to
  `seen` with “Return”. Both states can be cleared by swipe or Clear all.
- Swipe-to-clear changes that item to `cleared`.
- Clear all marks every currently visible item for the selected period
  `cleared` and stores the prior states in the Undo token. Undo restores those
  states if the token is still active. Items created later have new keys and
  remain eligible to appear.

## Recompute and period selection

The inbox retains an item when its claim stops qualifying for deduplication and
Undo state, but does not render it, count it in the badge, or offer a stale
drill-down. A fresh claim with the same key refreshes the snapshot and makes it
visible again; `cleared` state remains cleared.

Changing the Trends period filters the inbox to that calendar period. Claims
are reconciled only after fresh insights for the selected period are ready, so
period changes cannot briefly reconcile the new selection against old claims.
State is stored by key rather than current selection. Reconcile retains only
the current period and its previous three periods, even when the user selects a
historical period. The nav badge counts visible `new` items and announces the
count once.

## Persistence and rollback

State is stored in the existing `model_meta` key-value table under
`trends_inbox_v1`, as a versioned JSON map keyed by dedupe key. No schema change
is required; existing model metadata is included in encrypted backup and
restore. Corrupt or unsupported-version metadata is logged and copied as-is to
`trends_inbox_v1_backup` before the main key is repaired. The legacy
`insights.dismissed` bit remains claim-level state and maps to inbox `cleared`;
dismissal writes both states.

The `inboxEnabled` constant is the rollback switch. When false, Trends keeps the
existing fresh, non-dismissed claim feed and dismissal behavior. Inbox-only
state remains local metadata and is ignored by that feed.
