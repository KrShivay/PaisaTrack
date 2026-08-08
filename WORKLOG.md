# Current Handoff

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

## 2026-08-08 — T-156b bespoke sheet presenters routed through Bloom helpers

- Replaced `showModalBottomSheet` in `showCorrectionScopeSheet`,
  `showTransactionFilterSheet`, `_showSourceSms`, and `_askCategory` with
  `showBloomModalSheet` / `showBloomFullScreenSheet`. Wrapped
  `CorrectionScopeSheet` and `TransactionFilterSheet` bodies in
  `BloomSheetScaffold` to surface the Bloom handle. `_askCategory` now uses
  `showBloomFullScreenSheet(showBack: true)` matching the three other
  category-editor flows. Also removed `viewInsetsOf` keyboard padding from
  both sheet bodies since `showBloomModalSheet` handles it.
- Analyzer clean; 0 `showModalBottomSheet` calls remain in the four files
  (AC met). Commit 9a68ae2.

## 2026-08-08 — T-157a raw Drift writes routed through repositories

- Added `RecurringRepository.setStatus` and `InsightsRepository.dismiss`;
  both screens now call the repository instead of writing directly to the DB.
  Removed the now-unused `Value` show-imports from both screen files.
- Repository-level tests: 3 per repo, all against `NativeDatabase.memory()`; 6/6 pass.
- Analyzer clean. Neither screen calls `db.update(` directly (AC met).

## 2026-08-08 — T-159a correction/undo characterization tests complete

- Behavioral coverage for all four extraction targets: `_selectCategoryDirectly`
  and `_changeCategory` (detail screen) in a new
  `transaction_detail_correction_behavior_test.dart`; `_confirmItem` and
  `_recategorizeItem` (sort screen) added to `weekly_review_screen_test.dart`.
- Each test verifies the repository call fires, the undo token is pushed, and
  invoking the token reverts state. `_changeCategory` drives two sheets
  (picker + scope); `_confirmItem` tests revealed a bug where
  `updateWithFeedback(status:…)` is a no-op (flagged in spawned task).
- Verification: analyzer clean; T-159a suite **10/10**; commit below.

This is a rolling handoff, not a project history. Current product state is in
`docs/product-status.md`; unfinished work is in `TASKS.md`.
