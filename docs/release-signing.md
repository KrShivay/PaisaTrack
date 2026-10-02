# Android Release Signing Guide

PaisaTrack enforces release signing security for production builds.

## Setting Up Release Signing

### Option A: Local Build with `keystore.properties`

1. Generate an Android release keystore:
   ```bash
   keytool -genkeypair -v -storetype PKCS12 -keystore android/paisatrack-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias paisatrack_release
   ```

2. Create `android/keystore.properties` (the Android Gradle build reads this
   exact path):
   ```properties
   storeFile=../paisatrack-release.jks
   storePassword=YOUR_STORE_PASSWORD
   keyAlias=paisatrack_release
   keyPassword=YOUR_KEY_PASSWORD
   ```
   `storeFile` is relative to `android/app/`. Restrict the properties file to
   your user account (`chmod 600 android/keystore.properties`).

3. Build release bundle or APK:
   ```bash
   ./.tooling/flutter/bin/flutter build appbundle --release
   ```

## Previously published APK (0.1.3+2011)

The previously published download was `0.1.3+2011`, an ARM64 APK for 64-bit ARM
Android devices, built from the `pubspec.yaml` version at source commit
`3b2fb6b`. Flutter's
`--split-per-abi` build applies the ARM64 version-code offset of `2000`, so the
effective APK version code is `4011`. The published APK is 56,750,764 bytes
(56.75 MB decimal), with SHA-256
`218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`.
Its package is `com.paisatrack`, version name `0.1.3`, and production
certificate SHA-256
`6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
The artifact was built from main commit `3b2fb6b` with release version
`0.1.3+2011`. On 2026-09-30, this exact published artifact was installed with
`adb install -r` on the motorola edge 50 pro (Android API 36). The pulled
installed base APK matched the published size and SHA-256; package, version,
effective code `4011`, ARM64 ABI, and production signer matched. `firstInstallTime`
remained `2026-09-26 22:20:54`, confirming in-place replacement only; stored-data
integrity was not assessed. `MainActivity` launched and remained resumed. A
recent filtered AndroidRuntime/linker sample had no app fatal or native-load
failure markers. No private records were inspected, and optional inference
paths were not exercised. T-193 physical acceptance of the currency-repair
detail UI remains open. Broader T-167c responsive-layout, T-176 screen-inset,
T-179a key-recovery, T-177a capture/holdout, and T-194 size-trial acceptance
also remain open.

## Published APK (0.1.3+2012)

The signed ARM64 release was built from commit
`9f966992f8665c4f7fea72882af1270cb34b3c3b` with Flutter 3.44.4. It is
56,750,764 bytes with SHA-256
`d028507574978ede386a5c3a1560415f8551f502887ad87f89ed20f2da0bd403` and reports
package `com.paisatrack`, version `0.1.3`, effective ARM64 code `4012`, and
production certificate SHA-256
`6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`. The APK
contains only `arm64-v8a`, sets `extractNativeLibs=false`, and stores all six
native libraries uncompressed. ZIP integrity and `zipalign -c -v 4` passed;
the Android app and keystore Gradle unit-test tasks passed.

On 2026-10-01, this exact artifact was installed with `adb install -r` on the
motorola edge 50 pro. The pulled installed base APK matched its SHA-256, size,
and production signer; package code `4012` was installed and
`firstInstallTime` remained `2026-09-26 22:20:54`. This confirms in-place
replacement only, not stored-data integrity. The initial launch request
remained behind the Android keyguard; after the owner unlocked the phone, Ask
composer/close behavior passed bounded portrait checks at 1×, 1.5×, and 2× with
the real IME, and one 2× scroll exposed one prompt control. Landscape and other
routes remain untested. The exact artifact was published on `apk-downloads` in
commit `79614386e4f5271c5ccefc67eca66368642fb7ae`; the fetched public APK blob
matched the verified size and SHA-256 above. Broader device acceptance remains
open. Detailed evidence:
[2026-10-01 owner-phone install check](reports/release-v2012-owner-phone-install-2026-10-01.md).

## Published APK (0.1.5+2014)

Built from `21402a7` (main with T-177 R1–R3, schema v19 data migration and
the Home greeting copy fix) using the same split-per-ABI ARM64 command.
56,947,112 bytes, SHA-256
`9d9f14b20bb8ab817d19f295da93525fa25aa3292ab06c8d8b88794caa954c7f`, package
`com.paisatrack`, version `0.1.5`, code `4014`, production certificate
`6a00ef7a…9163`; arm64-v8a only, `extractNativeLibs=false`, six stored native
libraries, zipalign passed. The size equals 0.1.4+2013 because of 16 KB
alignment; `libapp.so` content differs and carries the new code. Android
Gradle unit tests app 31/31, keystore 10/10; Flutter suite 1136/1136.

On 2026-10-02 it replaced 4013 in place on the owner motorola edge 50 pro:
`firstInstallTime` unchanged, installed base APK hash matched. After unlock,
a cold launch (928 ms) opened the encrypted database (v19 migration applied
without error), Home showed the new "same days last month" greeting, and
Activity rows and the Trends inbox rendered with no app fatal or Flutter
error in logcat. No owner records were edited. Published on `apk-downloads`
in commit `738dd1ee8903a091c380e0b1846223396d93fb2e`; the fetched public blob
matched the SHA-256 above.

## Published APK (0.1.4+2013)

The signed ARM64 release was built from commit `7c1d1d0` (main after T-178a,
T-188, T-193, T-164e and UNDO-1) with Flutter 3.44.4 using
`flutter build apk --release --split-per-abi --target-platform android-arm64`.
It is 56,947,112 bytes with SHA-256
`c22bac44bf7f454c306fd9682ede101aed07e2969442ded3dd67b9e6da998ac4`, package
`com.paisatrack`, version `0.1.4`, effective ARM64 code `4013`, production
certificate SHA-256
`6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`. It contains
only `arm64-v8a`, sets `extractNativeLibs=false`, stores all six native
libraries uncompressed, and passes `zipalign -c -v 4`. Android Gradle unit
tests: app 31/31, keystore 10/10. Flutter suite at the source commit:
1083/1083.

On 2026-10-02 it was installed with `adb install -r` on the owner motorola
edge 50 pro: code 4013 / version 0.1.4 installed, `firstInstallTime` remained
`2026-09-26 22:20:54`, and the pulled installed base APK matched the SHA-256
above. A cold launch completed in 550 ms; the encrypted database opened and
Home, the floating navigation and the Trends inbox badge rendered with no app
fatal in logcat. No owner records were edited. Published on `apk-downloads`
in commit `ad6bb488a4ef9824d0215d78729be747d4d60787`; the fetched public blob
matched size and SHA-256. Known copy issue for the next build: the Home
greeting still says "than last month" although it now compares the same
elapsed days.

## Unpublished APK-size trial (T-194)

A signed ARM64 trial setting `jniLibs.useLegacyPackaging=true` on the release
variant through AGP's Variant API produced a
26,180,416-byte candidate (SHA-256
`cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`), a
30,570,348-byte reduction from the published artifact. Package, version,
effective ARM64 code, and production signing certificate match the published
APK. The candidate compresses all six native libraries and sets
`extractNativeLibs=true`; the same-source control build confirms all six
uncompressed library contents are unchanged by the packaging toggle.
The debug ARM64 build still has `extractNativeLibs=false` and uncompressed
native libraries.

This candidate has not been installed or published. Extraction is projected
to add about 23,069,324 bytes to installed storage relative to the current APK;
physical storage and cold-start impact remain unmeasured. The supported phone
was online for the separate published-release install/launch on 2026-09-30, but
the T-194 candidate was not installed or measured. Keep the published artifact
above unchanged, and leave T-194 open until its physical acceptance is recorded.

Resolve dependencies, then build from the repository root with:

```bash
./.tooling/flutter/bin/flutter pub get
./.tooling/flutter/bin/flutter build apk --release --no-pub --split-per-abi --target-platform android-arm64
```

The command produces `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
After verifying the signing certificate and installing it on ARM64 Android,
copy that file to `app-release-arm64.apk` on the `apk-downloads` GitHub branch.
The README links directly to that file. GitHub warns above
50 MB and rejects individual files of 100 MB or more, so use a GitHub Release
asset if a future APK exceeds that limit.

The current local signing files are `android/paisatrack-release.jks` and
`android/keystore.properties`. Both are git-ignored. Back up both files in a
secure location and preserve them for every future update: Android will reject
an update signed with a different key. Never copy either file into the APK
download branch or commit them to the source repository.

### Option B: CI/CD Build via Environment Variables

For automated CI lanes (GitHub Actions, Bitrise, Codemagic), pass the credentials via environment variables:

- `KEYSTORE_STORE_FILE`: Absolute path to decoded keystore file
- `KEYSTORE_STORE_PASSWORD`: Keystore password
- `KEYSTORE_KEY_ALIAS`: Key alias name
- `KEYSTORE_KEY_PASSWORD`: Key password

```bash
export KEYSTORE_STORE_FILE="/tmp/release.jks"
export KEYSTORE_STORE_PASSWORD="***"
export KEYSTORE_KEY_ALIAS="paisatrack"
export KEYSTORE_KEY_PASSWORD="***"
flutter build appbundle --release
```

## Security Rules

- **NEVER** commit `.jks`, `.keystore`, or `keystore.properties` to source control.
- Ensure `keystore.properties` and `*.jks` are listed in `.gitignore`.
