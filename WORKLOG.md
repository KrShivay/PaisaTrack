# Current Handoff

## 2026-09-30 — T-176 bottom-inset route acceptance

- Added real-route geometry checks using the production floating navigation
  pill and bottom-inset adapter around the actual Trends destination. Final
  content clears the pill with 24dp gesture and 48dp three-button insets at
  402×874, and at 568×320 landscape with 1.5× text. The harness uses a nested
  Navigator because mounting HomeShell leaves Drift stream cleanup timers
  pending; shell lifecycle acceptance remains open.
- Ask route diagnostic found a concrete unresolved issue: at 320×568, 2× text,
  and a simulated 220dp keyboard (348dp remaining height), the routed screen
  overflowed vertically by 42px and its send target was outside the 320dp
  viewport. This is recorded for investigation; no production change was made.
  Settings/Not transactions fixture cleanup also stalled. Detail/nested-sheet
  integration, Ask modal keyboard, 2× compact/landscape, tap behavior, and
  physical phone QA remain open. No emulator, private data, phone mutation, or
  APK change.
- Focused route tests 3/3; full Flutter suite 923/923; `flutter analyze
  --no-pub`, formatting, and diff check clean. GitNexus impact before symbol
  edits: `HomeShell` LOW and `BloomBottomInset` MEDIUM; no production symbols
  changed. Detect-changes: 2 files / 18 symbols, LOW risk, 0 affected
  processes.
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
  layout exception occurs. The existing AssistantScreen test continues to
  cover T-189's full-text vertical prompt rows and composer.
- Ask route and AssistantScreen tests pass 9/9; transaction detail/Note and
  full-screen sheet baseline pass 17/17; full Flutter suite passes 925/925;
  `flutter analyze --no-pub`, formatter, and diff checks are clean. GitNexus
  detect-changes reports LOW risk and no affected processes. T-176 remains open
  for Settings, detail/nested-sheet shell integration, landscape, tap behavior,
  and physical phone QA. No emulator, private data, phone mutation, or APK
  change.

## 2026-09-30 — T-189 readable Ask prompt list

- Replaced the three clipped horizontal composer chips shown after a chat
  starts with a scrollable vertical list of the same rotating catalogue
  prompts. Full text wraps, every row remains a labeled 48dp+ button, and
  sending or manually rotating advances the same three-question window. The
  initial searchable catalogue and local assistant contract are unchanged.
- Widget tests cover exact prompt text/send/rotation, semantics and target
  size, 320dp at 2× text, and final-row reachability plus composer placement in
  a keyboard-resized sheet. Assistant tests 7/7; full Flutter suite 924/924;
  `flutter analyze --no-pub`, formatter check, and diff check clean.
- GitNexus pre-edit impact: `_ComposerPromptChips` and `_AssistantScreenState`
  MEDIUM (13 affected symbols, 5 direct each). Detect-changes: 6 files / 24
  symbols, LOW risk, no affected processes. No data or schema changes.

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
  counterpart is detached from its omitted SMS and remains ineligible. No
  production code, schema, migration, private data, or APK changed.
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
- Published signed ARM64 `0.1.3+2008` to `apk-downloads`, commit
  `7971aeb7df39d210ae68a289fdff5debb20578ca`. APK size 56,750,764 bytes,
  SHA-256 `0f78b18200a899a2cddc9b4d7a02ecce6e18fe8a226e49103b168f910def3930`;
  package `com.paisatrack`, version name `0.1.3`, effective ARM64 code `4008`,
  production certificate SHA-256
  `6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
  Owner reports the in-place phone upgrade preserved firstInstallTime and left
  the app process alive without a crash exit. Synthetic encrypted
  backup/restore compatibility is now covered; physical repair-preview/apply/
  undo acceptance remains open.
