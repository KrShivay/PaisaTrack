# T-176 / T-167c physical Ask keyboard QA — 2026-09-30

## Scope and build

Physical smoke test of the production HomeShell → Ask PaisaTrack route on the owner’s motorola edge 50 pro. The phone was running the exact published ARM64 `0.1.3` / effective code `4011` APK, built from source commit `3b2fb6b` and signed with the production certificate. Main was at `5c98365`; its later clock/calendar work was not in this installed APK. Package `com.paisatrack` remained code `4011`, and `firstInstallTime` remained `2026-09-26 22:20:54`.

Only opened Ask, focused the empty composer, dismissed the IME, and closed Ask. No text was entered or submitted; no suggestion was selected; no transaction, SMS scan, permission, key, backup, reset, or restore operation was performed. No private financial values were read. A screenshot of the empty Ask route with the keyboard was inspected locally to confirm occlusion, then deleted; it is not attached or included here.

## Device and controls

- Physical display: 1220×2712 px at 450 dpi, approximately 434×964 dp. Android API 36.
- System bars in portrait: status bar 106 px; gesture navigation area 68 px (about 24 dp). Navigation mode was left unchanged; three-button mode was not tested.
- Default system font scale was 1.0. Ask opened from the bottom floating navigation. The Ask hit target measured 135×135 px (48 dp). The Ask close target also measured 135×135 px (48 dp).
- At 1.0 scale, the composer field before focus was `[104,2447][1009,2582]` px. After focusing and waiting for the IME to settle, it was `[104,2515][1009,2650]` px.

## Observed IME behavior

The physical IME became visible (`mInputShown=true`). WindowManager reported the IME frame `[0,1671][1220,2712]` px, a 1041 px (about 370 dp) bottom inset. The app configuration still reported the full portrait area, 434×964 dp. The composer’s post-focus bounds therefore fell entirely inside the IME-covered area. The local screenshot confirmed that the composer was not visible or tappable while the keyboard was open. The close target remained visible at the top.

Prompt controls were present before focus and within the portrait content bounds. With the IME open, lower prompt rows extended under the keyboard; their visible geometry was partly covered. No suggestion was activated. This is a physical keyboard acceptance failure for the HomeShell → Ask composer at default scale.

At 1.5 font scale, the same portrait route was checked. The system and app configuration reported 1.5. Before focus, prompt controls and both Ask fields had nonzero bounds in the viewport. After focusing the composer, the IME again began at y=1671 px and the composer was at `[104,2514][1009,2652]` px, fully under the IME; lower prompt controls were also covered. Thus physical IME acceptance also failed at 1.5 scale.

The system font scale was briefly changed to 2.0 while returning to Home, but no 2.0 route or keyboard acceptance is claimed. Landscape was not tested. Original values were restored and verified: font scale `1.0`, `accelerometer_rotation=1`, `user_rotation=0`; orientation stayed portrait. The app was left on Home with the IME hidden. No system navigation setting changed.

## Evidence versus hypothesis

Confirmed: the manifest declares `windowSoftInputMode="adjustResize"`; with the physical IME visible, Android still reported the full app configuration and a nonzero IME inset, while the focused composer remained behind the keyboard. The screenshot and sanitized accessibility bounds agree on the occlusion.

Likely route-level cause, for code review: `showBloomFullScreenSheet` uses a full-height `FractionallySizedBox` and `BloomSheetScaffold`; `AssistantScreen` lays out a `SafeArea`/`Column` without applying `MediaQuery.viewInsets`. The shared `showBloomModalSheet` helper does apply bottom padding for `viewInsets`. Existing Ask route tests simulate a shorter physical size with zero viewInsets, so they do not cover a full-height window with the real nonzero IME inset. This is a hypothesis for the keyboard-fix owner to verify, not a confirmed diagnosis.

## Remaining acceptance

T-176 and T-167c remain open. This was only the Ask route on one phone in portrait, at 1.0 and 1.5 font scales. 2.0 scale, landscape, three-button navigation, other T-176 routes, and the rest of the T-167c device matrix remain untested. This smoke test does not establish stored-data integrity or complete release acceptance.


## Fix-branch verification (not physical reacceptance)

The T-176 implementation branch adds an opt-in bottom-inset owner to the full-screen sheet route and enables it only for HomeShell → Ask. Ask chooses its compact header from the available route height after subtracting the reported IME inset. Other full-screen callers keep their existing inset behavior, and descendant `MediaQuery.viewInsets` remains available to nested routes.

A regression-first direct Ask route test failed before the fix: with a 568 dp full window and a 220 dp IME inset, the Ask composer ended at 548 dp, below the 348 dp visible bottom. It now checks the compact 48 dp close target, scrollable prompt visibility, and unchanged viewInsets at 1.5× text. The production HomeShell integration test taps the actual navigation pill and checks both 320×568/2× with a 220 dp inset and a phone-like 434×964/1× viewport with a 370 dp inset; each case clears the IME, closes Ask, and returns to Home. The direct Ask route suite also covers a 348 dp resized window with zero residual inset. A full-screen-helper test opens and closes a nested modal while the inset remains present. These are synthetic widget tests; the owner phone still runs the earlier published build, so physical acceptance remains failed and open until the reviewed fix is installed and rechecked.
