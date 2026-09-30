# Current Handoff

## 2026-09-30 — T-177a capture-decision version contract

- Read-only audit confirmed the prior synthetic replay already covered live,
  history, and resume providers. The report keeps the intentional wiring gaps:
  live may use the optional field locator and merchant resolver; history/resume
  omit those helpers, use fixed review status, and do not activate merchant
  memory, LLM categorization, or shadow execution.
- Added the shared `capture_decision` writer/reader contract to the existing
  `confidence_json` block. Parsed rows record `capture-decision-v1` and explicit
  `policy` (live) or `fixed_review` (history/resume) status mode. Legacy,
  malformed, and unsupported metadata reads as unknown; no row is backfilled.
  ADR 0018 documents versioning, backup/deletion compatibility, and that the
  marker is not a correctness label. No schema, generated code, inference, or
  category behavior changed.
- Updated the replay fixture to read persisted decision versions and assert the
  status mode from all three synthetic production provider paths. No real SMS,
  phone, emulator, network, or private user data was used; no accuracy or
  holdout claim is made. T-167c moved to Ready with physical-device QA pending.
- Pre-edit GitNexus impact was HIGH for `_transactionCompanionFor` (9 symbols,
  4 flows) and CRITICAL for `SmsIngestor` (29 symbols, 16 direct, 6 flows).
  The history/resume provider impact returned UNKNOWN; text search confirmed the
  actual call sites. HIGH/CRITICAL warnings were delivered before edits.
  Independent review found and rechecked the fixed-status mode edge with no
  blocker.
- Focused provenance/ingest/backfill tests passed 57/57; full Flutter suite
  passed 942/942; `flutter analyze --no-pub` and `git diff --check` are clean.
  GitNexus final graph detection: 10 files, 28 symbols, 0 processes,
  LOW. Real chronological holdout and physical capture/resume coverage remain
  open.

## 2026-09-30 — T-167c Weekly Review compact-landscape slice

- Reproduced the fixed Weekly Review card/action `Column` overflow through the
  production Sort navigation route: 30dp at 568×320/1.5×/24dp gesture inset
  and 86dp at 568×320/2×/48dp three-button inset; at 2× the card could not be
  tapped. GitNexus pre-edit impact for `_buildCardView` was LOW and exact (one
  direct caller, `build`, and one affected screen process/module).
- In compact landscape, the header/card/action spacing now adapts, secondary
  progress content gives room to the card, and the card scrolls vertically.
  Horizontal swipe recognition remains horizontal so user vertical drags reach
  the scrollable card. The 20dp title style still respects the user's text
  scaler. `SafeArea` handles the compact bottom inset; portrait keeps the prior
  layout and bottom-inset spacer.
- Added real shell-route tests with the production floating pill and synthetic
  provider data at 402×874/default text, 568×320/1.5×/24dp, and
  568×320/2×/48dp. They assert no layout exception, title top and bottom are
  reachable with vertical finger drags, the action clears the pill, a visible
  card intersection opens production transaction detail, and Skip advances to
  the next item. No data/provider behavior changed.
- Global bottom-inset route suite passed 14/14; all Review tests passed 26/26
  (including existing swipe/detail/persistence coverage). Full Flutter suite
  passed 939/939; `flutter analyze --no-pub`, changed-file formatting, and
  `git diff --check` are clean. GitNexus pre-commit graph detection found 4
  changed files, 11 changed symbols, 0 affected processes, LOW risk, with no
  partial/truncated result. Independent review approved the updated diff. No
  phone/emulator, private transaction data, mutation, or APK was used. T-176
  remains Ready with physical-device QA pending; T-167c moved to Ready with
  physical QA still open.

## 2026-09-30 — T-176 bottom-inset route acceptance

- Added five Settings→Not transactions route cases using synthetic in-memory
  rows. The Settings action and last history row clear the production pill at
  24dp/48dp insets on 402×874, 320×568 at 2× text, and 568×320 at 1.5×/2×;
  each case taps the action and restores the last row. Flutter's default
  `ListView` padding consumes the adapter's `MediaQuery.padding.bottom`, so no
  inset production change was needed.
- Restore tapping exposed a `setState` callback that returned the `_load()`
  Future; it now assigns `_rows` inside a synchronous callback. The compact
  2× route exposed a `ListTile` trailing-width assertion; date and amount now
  wrap on separate subtitle lines. Drift teardown was traced to closing the DB
  only in `addTearDown`, after Flutter removes stream subscribers; the fixture
  now unmounts and closes the in-memory DB in `finally` before test teardown.
- The original Trends checks remain: final content clears the pill at both
  navigation insets on 402×874 and at 568×320/1.5×. The route harness uses a
  nested Navigator with the production pill/adapter. Added a separate
  `HomeShell` route test that opens Ask from the real pill at 402×874 with
  simulated 24dp/48dp safe padding, then checks the 320×568/2× route after a
  synthetic adjustResize to 320×348 with zero residual inset. The composer and
  48dp close target stay inside the resized route. The shell fixture keeps the
  database unopened and unmounts explicitly, so it does not create Drift stream
  cleanup timers. The isolated HomeShell Activity nested-Navigator test also
  passes. Physical keyboard behavior remains unverified; Ask modal-route device
  acceptance, remaining compact/landscape combinations, and physical phone QA
  remain open. No emulator, private data, phone mutation, or APK change.
- Added Activity→detail→correction coverage through the real
  `TransactionsScreen` route with the production pill/adapter. The Activity row
  clears the pill and opens detail at 402×874/24dp/1×, 568×320/24dp/1.5×, and
  568×320/48dp/2×; the detail edit action opens the nested correction sheet,
  where changing the direction ChoiceChip succeeds. No inset/tap defect was
  demonstrated in this route, so production code is unchanged.
- Attempting the separate Sort→detail caller at 568×320 reproduced
  `WeeklyReviewScreen`'s fixed card/action Column overflowing by 30dp at
  1.5×/24dp gesture inset and 86dp at 2×/48dp three-button inset; the card is
  outside the viewport at 2× and cannot be tapped. Existing Weekly Review tests
  use portrait fixtures and miss compact landscape; the layout follow-up is
  tracked under T-167c and is outside this T-176 slice.
- Focused route suite 11/11; production HomeShell→Ask suite 3/3; existing
  HomeShell Activity nested-Navigator test 1/1; full Flutter suite 936/936;
  `flutter analyze --no-pub`, changed-file formatting, and `git diff --check`
  clean. The previous Activity/detail/correction slice's GitNexus
  detect-changes saw 3 files, 18 symbols, 0 affected processes, LOW risk. This
  HomeShell/Ask slice's pre-commit GitNexus detect-changes saw 3 files, 5
  indexed documentation symbols, 0 affected processes, LOW risk. Pre-edit
  `TransactionDetailScreen` impact was HIGH (43 symbols, 18
  direct callers, one process); no production detail code changed. Earlier
  `NotTransactionsScreen` impact was LOW (6 symbols, one direct caller, no
  affected processes). No emulator, private data, phone mutation, or APK
  change.
- T189 was removed from the active board after independent Luna review of
  implementation `48df299` and documentation fix `b73f7cb` found no functional
  blocker. Its brief now records completion and the reviewed prompt, target,
  keyboard, semantics, tap, and rotation evidence.
