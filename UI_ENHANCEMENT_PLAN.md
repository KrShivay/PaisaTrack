# PaisaTrack — Dashboard & UI Enhancement Plan

Separate, self-contained plan for enriching the dashboard with meaningful stats
beyond balance, and lifting the overall UI polish. Follows `docs/design-system.md`
(calm confidence, numbers-first, dark-first, one accent per screen).

## 1. Current State

The dashboard (`lib/features/dashboard/dashboard_screen.dart`) renders exactly
two cards derived from `monthDirectionTotalsProvider`: **Spent** and **Received**
for the current calendar month. No trends, no breakdowns, no comparisons. All
required raw data already exists on `TransactionListItem` (ts, amount, direction,
displayName, categoryName/Id/Icon) and `NormalizedTransactionRecord` (channel,
balanceAfter), so most stats below are pure in-memory derivations — no schema or
DB changes needed.

## 2. Goals

- Show stats **other than balance**: spending trend, category breakdown, top
  merchants, net flow, daily burn rate, and month-over-month comparison.
- Keep the design calm: amounts are the loudest element, at most one gold accent
  per screen, semantic debit/credit color on amounts only.
- Zero new dependencies where possible; reuse `formatInr`, `PaisaColors`,
  `AppSpacing`, `AppTheme.tabularFigures`.

## 3. Proposed Dashboard Layout (top → bottom)

1. **Month header** — current month name + net flow chip (Received − Spent),
   colored credit/debit. Replaces the bare "This month" title.
2. **Summary row** — the existing Spent and Received cards, condensed into a
   two-up compact row to reclaim vertical space.
3. **Net & pace strip** — three small stat tiles:
   - *Net this month* (Received − Spent)
   - *Daily average spend* (Spent ÷ days elapsed)
   - *vs last month* (percent change in spend, arrow up/down)
4. **Spending by category** — horizontal bar / donut of top 5 categories with
   amount and share; uses `categoryIcon` + category color. "Uncategorised"
   bucketed last.
5. **Top merchants** — top 3–5 `displayName` by total debit this month, each with
   count and amount.
6. **Trend sparkline** — last 6 months net spend as a minimal sparkline (no axes,
   one line) for at-a-glance direction.

Sections 4–6 collapse gracefully (hidden or "not enough data" state) when the
month has few transactions.

## 4. New Providers (in `dashboard_providers.dart`)

All derive from `transactionListProvider` in memory, matching the existing
`monthDirectionTotalsProvider` pattern (no second DB query):

- `monthNetProvider` → `double` (creditTotal − debitTotal).
- `dailyAverageSpendProvider` → `double` (debitTotal ÷ days elapsed in month).
- `monthOverMonthSpendProvider` → `{ current, previous, pctChange }`.
- `categoryBreakdownProvider` → `List<CategorySlice>` (id, name, icon, total,
  share), debit only, sorted desc, top N + "Other".
- `topMerchantsProvider` → `List<MerchantStat>` (displayName, count, total),
  debit only, top N.
- `sixMonthTrendProvider` → `List<MonthPoint>` (month, spend) for the sparkline.

Each provider gets a unit test mirroring `test/features/dashboard/`.

## 5. New Widgets (in `lib/features/dashboard/widgets/`)

- `StatTile` — compact label + value tile for the net/pace strip.
- `CategoryBreakdownCard` — bar rows using category color + icon + share.
- `TopMerchantsCard` — ranked merchant rows.
- `TrendSparkline` — custom-painted single-line sparkline (no chart lib), or a
  minimal `fl_chart` line if we accept one dependency (decision in §7).
- `NetFlowChip` — colored pill for the month header.

Refactor `_TotalCard` into a shared `SummaryCard` and add a compact variant.

## 6. Phased Delivery

**Phase 1 — Stats foundation (no new deps)**
Add the six providers + tests; add the net/pace strip and month header. Ship
value immediately with zero visual risk.

**Phase 2 — Breakdowns**
Category breakdown card + top merchants card, with empty/low-data states.

**Phase 3 — Trend & polish**
Six-month sparkline, compacted summary row, spacing/motion pass, light+dark
verification.

## 7. Open Decisions

- **Charting:** hand-painted sparkline/bars (zero deps, full control, matches
  "quiet" aesthetic) **vs** adding `fl_chart` (faster, heavier). Recommendation:
  hand-paint bars and sparkline; revisit `fl_chart` only if a richer chart is
  requested.
- **Time window:** fixed calendar month (current behavior) **vs** rolling 30
  days. Recommendation: keep calendar month for the summary, use rolling 6
  months only for the trend.
- **Scroll:** dashboard becomes taller than one screen — wrap body in a
  `ListView`/`CustomScrollView`.

## 8. Risks & Guardrails

- Per project rules (`CLAUDE.md`): run `impact({target, direction:"upstream"})`
  before editing `DashboardScreen`, `_TotalCard`, or `monthDirectionTotalsProvider`,
  and `detect_changes()` before committing. Widget extraction is low blast-radius
  but verify.
- Performance: all stats are O(n) over the already-loaded month/6-month list;
  compute once per provider, no nested loops over full history.
- Design review: debit/credit color only on amounts; gold used at most once
  (reserve for a single "insight" moment, e.g. the vs-last-month callout).

## 9. Definition of Done

- Dashboard shows net flow, daily average, month-over-month, category breakdown,
  top merchants, and a 6-month trend — all beyond the raw balance.
- New providers covered by unit tests; `flutter analyze` clean.
- Verified in both light and dark themes; empty and single-transaction states
  render without overflow.
