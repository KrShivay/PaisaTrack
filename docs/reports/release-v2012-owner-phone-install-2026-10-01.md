# Release 0.1.3+2012 owner-phone install check — 2026-10-01

## Artifact

The production-signed ARM64 APK was built from release branch commit
`9f966992f8665c4f7fea72882af1270cb34b3c3b` with Flutter 3.44.4. The only source
change from main commit `3d5f310` is the version metadata bump to `0.1.3+2012`.
The APK is 56,750,764 bytes with SHA-256
`d028507574978ede386a5c3a1560415f8551f502887ad87f89ed20f2da0bd403`. It reports
package `com.paisatrack`, version name `0.1.3`, effective ARM64 version code
`4012`, ARM64-only ABI, and production certificate SHA-256
`6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`. The
manifest has `extractNativeLibs=false`; all six ARM64 native libraries are
stored uncompressed. ZIP integrity and `zipalign -c -v 4` passed. Android app
and keystore Gradle unit-test tasks passed.

## In-place install evidence

On 2026-10-01, the USB-connected motorola edge 50 pro (Android API 36) was
identified as serial `ZD222KTYNC`. Before installation, package
`com.paisatrack` reported version `0.1.3` / code `4011`; the pulled base APK
matched the published 4011 artifact at 56,750,764 bytes and SHA-256
`218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`.
Installation used `adb install -r` on the verified 4012 artifact and returned
`Success`. Afterwards, the package reported version `0.1.3` / code `4012`; the
pulled installed base APK matched the candidate size, SHA-256, and production
signer. `firstInstallTime` remained `2026-09-26 22:20:54`, confirming an in-place
package replacement only; stored-data integrity was not assessed.

## UI acceptance status

After the owner unlocked the phone, `MainActivity` became foregrounded. Ask was
opened through the production bottom navigation pill, and the empty composer
was focused without entering text. The portrait display measured 1220×2712 px
at 450 dpi (about 434×964 dp); the system reported a full-height app window
with a real nonzero IME inset.

- At 1× font scale, the IME frame was `[0,1671][1220,2712]`. The focused
  composer measured `[104,1474][1009,1609]`, 62 px above the visible bottom.
  Prompt controls remained above the IME, and the close target measured
  `[1051,171][1186,306]` (135×135 px, 48 dp).
- At 1.5×, the IME frame was `[0,1373][1220,2712]`. The composer measured
  `[104,1175][1009,1313]`, 60 px above the visible bottom; the close target
  remained 135×135 px. One prompt control was visible above the keyboard.
- At 2×, the IME frame was `[0,1315][1220,2712]`. The composer measured
  `[104,1115][1009,1256]`, 59 px above the visible bottom; the close target
  remained 135×135 px. One safe vertical swipe in the scroll viewport exposed
  a suggestion control at `[56,888][1164,1090]` above the keyboard. No prompt
  was selected. This confirms one scroll-reachable control, not readability of
  every suggestion or full large-text acceptance.

The Ask close target was tapped at 2× with the keyboard visible; the IME hid and
the app returned to Home. Font scale was restored from `2.0` to `1.0`; rotation
settings remained `accelerometer_rotation=1` and `user_rotation=0`. Final checks
showed the IME hidden, keyguard clear, and `firstInstallTime` unchanged. No
messages were entered or submitted, no suggestions were selected, no
transactions were edited, and no clear, reset, restore, or backup operation
was performed. No private financial text or records were inspected.

The 4012 artifact was published on `apk-downloads` in commit
`79614386e4f5271c5ccefc67eca66368642fb7ae`; the fetched public APK blob matched
the verified size and SHA-256. T-176 still needs landscape,
three-button navigation, and other route coverage; T-167c and broader release
device acceptance remain open. This check does not establish stored-data
integrity or complete release acceptance.
