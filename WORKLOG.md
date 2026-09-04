# Current Handoff

## 2026-09-04 — PV-02 truthful dashboard aggregates + review fixes

- **PV-02 (loading/error half):** The ~10 dashboard/insights aggregate-derived
  providers (`monthDirectionTotals`, `monthNet`, `dailyAverageSpend`,
  `safeToday`, `runway`, `projectedMonthEnd`, `monthOverMonthSpend`,
  `categoryBreakdown`, `topMerchants`, `sixMonthTrend`) now project
  `dashboardAggregateProvider` as `AsyncValue` and no longer fall back to the
  bounded 100-row `transactionListProvider`. Hero ring, budget card,
  top-categories, and the four insights sections render distinct loading/error
  states (skeleton / inline error). Removed `_countsAsSpending` (weaker than the
  SQL `FinancialEligibility` contract; it omitted `lifecycle_state='settled'`).
  Completeness/exclusion disclosure remains open on PV-02.
- **Trend timezone:** `_loadTrend` no longer uses SQLite `'localtime'`; it
  buckets with an explicit `DashboardQueryWindow.timeZoneOffset` threaded from
  `FinancialCalendar`, so month grouping honours the same calendar as the rest
  of analytics and is deterministic under an injected offset.
- **Sender blacklist:** added a "Block a sender" control + dialog in Settings —
  `pausedSenders` was enforced/displayed/removable but had no add path.
- **Docs:** refreshed `product-status.md` (status date; stale BloomCategoryTile
  fallback-glyph claim); updated PV-02 scope note in `TASKS.md`.
- Verified: `flutter analyze --no-pub` clean; full `flutter test` **732 passed,
  2 failed** — both failures (`exclusion_explanation_test.dart`) are
  **pre-existing on `main`** (they assert the CC-bill exclusion behaviour that
  T-158d intentionally removed), unrelated to this change. `detect_changes`:
  50 symbols / 4 processes, all expected.

## 2026-08-08 — T-157b shared correction/undo controller

- Added `TransactionCorrectionController` to centralize database resolution,
  repository mutation, and undo-token registration for transaction detail and
  Sort. Optimistic queue/category presentation and existing repository contexts
  remain in the screens through callbacks.
- Repointed `_changeCategory`, `_selectCategoryDirectly`, `_confirmItem`, and
  `_recategorizeItem`; cleaned six pre-existing analyzer infos in T-159b tests.
- Focused Review/Detail correction suite: 20/20 passed. `flutter analyze
  --no-pub`: no issues found.

## 2026-08-08 — T-158d exclusionReasonFor parity fix

- Removed 2 merchant-pattern branches (CREDIT CARD/CARD BILL and ATM/WITHDRAWAL)
  from `exclusionReasonFor`. These fired when neither `ownedTransferId` nor
  `isAnalyticsExcluded` was set — i.e., the banner claimed exclusion for
  transactions that `FinancialEligibility` SQL actually counts. CC bill payments
  between untracked accounts and ATM withdrawals not yet categorized were both
  affected. Only the two flags that drive SQL exclusion now produce a banner.
- Updated 4 tests: 2 patterns-alone → now expect null; CC+isAnalyticsExcluded
  priority test reworded. 29/29 passing, analyzer clean.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
