# T-176 + T-167c Android emulator matrix — 2026-10-02

> **Status (2026-10-03):** superseded in part. This report records the first
> emulator pass only. A later harness round found real defects (Ask catalogue
> rows below 48dp, the clipped "Parsed locally" badge, the landscape hero
> ring), fixed in `82ba900`; owner-phone checks then found and fixed
> horizontal-inset and short-height Activity issues (`9dac2c5`). The harness
> in `tool/qa/emulator_layout_matrix.py` was stopped mid-iteration and is kept
> as an unfinished emulator-only tool (it refuses non-emulator devices).
> Acceptance for T-176/T-167c remains open pending the physical recheck.

## Result

This is **emulator evidence, not physical acceptance**. The requested 12-cell matrix was not completed: only the baseline portrait/gesture/1.0 routes and Sort at landscape/three-button/2.0 received live emulator checks. Unvisited cells are marked NR; they are not passes. No real layout defect was confirmed in the exercised routes, so no source fix or new failing-first regression test was appropriate. Acceptance remains open.

## Device and setup

- Device: `emulator-5554`, Android API 35, `ro.kernel.qemu=1` verified before each install/settings/input batch.
- Tested override: 1220×2712 px at density 450 (about 434×964 dp); landscape by rotation; font scales noted per cell.
- App: debug APK, `com.paisatrack`, built for `android-arm64` and installed on the emulator only.
- Synthetic SMS only; inbox scan reported 34 scanned, 0 rejected, 5 unknown sender, 29 accepted, 0 parsed, 0 unparsed, 0 created, 28 already known. One unknown ₹600 row was marked “Not a transaction” in the UI. Sort showed 26 queued items. No personal message content was used.
- Screenshot review and `uiautomator dump` bounds were used for the listed checks. Bounds below are physical pixels; at density 450, 135 px is 48 dp.

## Matrix

Legend: **P** = exercised and passed visual/geometry/tap checks; **Partial** = route checked with the noted route-level gap; **NR** = not run. “Detail/Edit” covers opening a transaction detail and its Parse Details correction sheet with the IME visible. Period covers the selector and custom range picker. Every named route inherits its cell status.

| Navigation | Orientation | Font | Home | Activity | Detail/Edit | Sort | Trends | Settings | Not transactions | Ask + IME | Period/custom |
|---|---|---:|---|---|---|---|---|---|---|---|---|
| Gesture | Portrait | 1.0 | P | Partial | P | NR | P | P | P | P | P |
| Gesture | Portrait | 1.5 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| Gesture | Portrait | 2.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| Gesture | Landscape | 1.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| Gesture | Landscape | 1.5 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| Gesture | Landscape | 2.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Portrait | 1.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Portrait | 1.5 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Portrait | 2.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Landscape | 1.0 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Landscape | 1.5 | NR | NR | NR | NR | NR | NR | NR | NR | NR |
| 3-button | Landscape | 2.0 | NR | NR | NR | P | NR | NR | NR | NR | NR |

Activity was visibly checked to the end of its available list, with eight settled rows, but this seeded dataset did not expose a “Load more” action. Its specific acceptance is unverified, hence Partial. Display-size variation was not separately checked.

## Observed geometry

All measurements are from the 1220×2712 portrait / 2712×1220 landscape emulator override unless otherwise stated.

| Route / state | Observed bounds (px) | Result |
|---|---|---|
| Home, scrolled end | Last “About these totals” content ends at y=2408; floating nav pill starts y=2430 | 22 px visible gap; no clipped end content observed |
| Activity, list end | Last visible row ends at y=2408; pill starts y=2430 | Clear of pill; no Load more control present in this data state |
| Trends, scrolled end | Top Merchants section ends at y=2408; pill starts y=2430 | Clear of pill; screenshot showed no clipped text |
| Ask with IME settled | Close target `[1051,219][1186,354]` (135×135); composer `[104,1570][1009,1705]`; IME touch frame starts y=1767 | Close target is 48 dp; composer ends 62 px above IME; prompt suggestions readable and scrollable |
| Edit Parse Details with numeric IME | Save Correction `[56,1700][1164,1835]`; IME touch frame starts y=1891 | Save ends 56 px above IME; action fully visible |
| Settings, scrolled end | Last Delete all local data action ends y=2295; pill starts y=2430 | 135 px clearance |
| Not transactions | History row `[0,312][1220,565]` | Final/only seeded row visible and tappable |
| Period selector | Custom date range action `[56,2453][1164,2610]` | Above gesture system area; range picker opened and calendar screenshot showed header/actions |
| Sort, landscape / 3-button / 2.0 | Card `[210,242][2521,826]`; action targets 135×135 px; right-side nav bar `[2577,0][2712,1220]`; nav pill starts y=1006 | Card and actions clear of system/nav areas; screenshot showed no clipping |

The Sort landscape check used font scale 2.0 and three-button navigation; 135 px action targets equal 48 dp at density 450. No display-size variant was tested.

## Defects and code changes

No confirmed responsive/inset/keyboard layout defect was found in the states actually exercised. Transient clipping-looking content during scroll disappeared after reaching the route’s scroll end; it was not a persistent defect. No source files or tests were changed. The live checks do not establish behavior for the 10 unvisited configuration cells or for Activity’s unavailable Load more state.

## Verification

- `flutter build apk --debug --target-platform android-arm64`: passed.
- Focused responsive/route suite: 25/25 passed (`global_bottom_inset_acceptance_test.dart`, `assistant_route_keyboard_test.dart`, `home_shell_ask_route_test.dart`, `transaction_detail_correction_test.dart`).
- Full `flutter test`: 986 passed, 1 failed. Failure: `test/intelligence/recurring_detector_test.dart`, “large single-merchant histories are clustered in bounded time” (not a layout test). A focused rerun of that test passed (1/1), so the full-suite failure was not reproducible in isolation; its cause is unconfirmed.
- `flutter analyze --no-pub`: passed, no issues found.
- `dart format --output=none --set-exit-if-changed lib test`: failed because 38 files already in the clean base tree are not formatted by the pinned Dart formatter. No Dart files changed in this task, and none were formatted to avoid unrelated edits.
- `git diff --check`: passed before this report was added.
- GitNexus impact before any source edit: CLI index was created for this worktree because MCP had no index for its path. `AssistantScreen`, `WeeklyReviewScreen`, `DashboardScreen`, and `HomeShell` impacts were all LOW; no HIGH/CRITICAL result. The indexed process graph was partial/truncated, and unresolved dynamic/property call sites remain a limitation.
- GitNexus `detect-changes --scope all`: “No changes detected.” The report is the only untracked file; no tracked source changes were made.

## Emulator hygiene

Restored and read back: physical size 1080×2400, density 420, font scale 1.0, accelerometer rotation enabled, user rotation 0 (portrait), secure navigation mode 2 (gesture). All device operations remained on `emulator-5554` after verifying `ro.kernel.qemu=1`.
