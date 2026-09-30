# Current Handoff

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

## 2026-09-30 — T-176 Ask compact keyboard route

- Corrected the route harness to model one keyboard resize: it opens the real
  full-screen Ask sheet at 320×568 and 2× text, then changes the viewport to
  320×348 with zero residual `viewInsets`, matching the app's Android
  `adjustResize` contract. The previous 42px overflow measurement combined a
  348dp resized viewport with a second 220dp inset and overstated the failure.
- The corrected route-size-only test still exposed a production layout issue:
  the full Ask header title and subtitle wrapped to 138dp and 155dp at 2×,
  leaving 23dp for the assistant content. Added an Ask-only compact header
  below 400dp; normal-height header remains unchanged. At 320×348 the composer
  remains visible, close target is 48dp, transcript remains scrollable, and no
  layout exception occurs. A real prompt submission now verifies the user
  message's own transcript ListView has positive scroll extent and the answer
  appears after scrolling. The AssistantScreen prompt panel is capped to leave
  transcript space in 96–240dp content heights; prompt rows remain 48dp+ and
  scrollable. Its keyboard regression now uses a 348dp viewport with zero
  residual inset instead of applying both resize and inset.
- Ask route and AssistantScreen tests pass 9/9; transaction detail/Note and
  full-screen sheet baseline pass 17/17; full Flutter suite passes 925/925;
  `flutter analyze --no-pub`, formatter, and diff checks are clean. GitNexus
  detect-changes reports LOW risk and no affected processes. T-176 remains open
  for Settings, detail/nested-sheet shell integration, landscape, tap behavior,
  and physical phone QA. No emulator, private data, phone mutation, or APK
  change.

## 2026-09-30 — T-193 legacy currency repair

- The source-backed per-transaction detail preview/apply/undo repair was
  independently reviewed with no blocker. It requires retained/unexpired
  linked SMS, exact amount evidence matching the body and stored paise, and one
  adjacent `Rs`/`Rs.`/`INR`/`₹` token; it changes only currency fields and
  preserves later edits on undo. USD, bare `$`, manual/imported/unknown,
  duplicate/deleted, stale, mismatched, or expired cases remain unchanged.
- Added a synthetic encrypted chunked-backup restore integration test. A legacy
  null-currency transaction with retained raw SMS and amount evidence remains
  previewable after restore and successfully applies/undoes INR. Its expired
  counterpart is detached from its omitted SMS and remains ineligible. The
  compatibility test changes no production code, schema, migration, private
  data, or release artifact.
- Focused backup and repair-service tests 40/40; full Flutter suite 915/915;
  `flutter analyze --no-pub`, changed-file formatting, and diff check clean.
  GitNexus detect-changes: 9 documentation section symbols in TASKS, WORKLOG,
  and T-193 notes, LOW risk, no affected processes (the test file has no
  indexed symbols).
  Pre-edit test-scope impact: `SourceCurrencyRepairService` HIGH (31 symbols)
  and `EncryptedBackupService` HIGH (27); neither production class was edited.
  The encrypted restore compatibility-test commit independently reviewed
  without a blocker. Physical UI preview/apply/undo confirmation remains
  pending.
- Published signed ARM64 `0.1.3+2010` to `apk-downloads`, commit
  `00952c8cb86f8e45a4e731e8b7d8bf8a0dc21011`. APK size 56,750,764 bytes,
  SHA-256 `55d0548ed6c82746d26861377106da1efaff0ace1ec146f43ebf337ebb133944`;
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4010`,
  production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
  The in-place phone upgrade preserved `firstInstallTime` (`2026-09-26
  22:20:54`); the app launched with live PID 16774 and the newest exit-info
  entry was `PACKAGE UPDATED`. Synthetic encrypted backup/restore
  compatibility is covered; physical repair-preview/apply/undo acceptance
  remains open.
