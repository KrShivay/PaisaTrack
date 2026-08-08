# Current Handoff

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

## 2026-08-08 — T-159b unit tests for extracted pure functions

- Added `test/features/transactions/detail/transaction_detail_formatting_test.dart`
  (30 tests across `chipCategories`, `exclusionReasonFor`, `formatDetailDate`,
  `parserSourceLabel`) and `transaction_detail_evidence_test.dart` (13 widget
  tests for `buildEvidenceSpans`). Fixed 2 wrong assertions in `chipCategories`
  — the function always fills to 3 chips from `allCategories` fallback; tests
  now verify the skip behavior without over-constraining total count.
- 43/43 passing. Low risk (test-only, no affected execution flows).

## 2026-08-08 — T-158a pure functions extracted from transaction_detail_screen

- Extracted `chipCategories`, `exclusionReasonFor`, `formatDetailDate`,
  `parserSourceLabel` into new `detail/transaction_detail_formatting.dart`;
  extracted `buildEvidenceSpans` + `_highlightColorFor` into new
  `detail/transaction_detail_evidence.dart`.
- Removed `_formatDate`/`_shortMonth` instance methods from
  `_TransactionDetailScreenState`; `_SourceMessageEvidenceView.build()` is
  now a one-liner delegate. All five functions are now unit-testable without
  pumping the full screen widget.
- Analyzer clean; 0 affected processes (pure refactor). Commit 834ae42.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
