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

## Published APK

The currently published download is `0.1.3+2011`, an ARM64 APK for 64-bit ARM
Android devices, built from the current `pubspec.yaml` version. Flutter's
`--split-per-abi` build applies the ARM64 version-code offset of `2000`, so the
effective APK version code is `4011`. The published APK is 56,750,764 bytes
(56.75 MB decimal), with SHA-256
`218308d98cd8b0105adfe74d5e49cae5183ddb964f889e419ed5199888be50c4`.
Its package is `com.paisatrack`, version name `0.1.3`, and production
certificate SHA-256
`6a00ef7a3557533e091011d6166c0c45a3bc7a1e540dd2eed4640c88c1ed9163`.
The artifact was built from main commit `3b2fb6b` with release version
`0.1.3+2011`. Physical v2011 launch is unverified because the device is
offline; the phone remains on `0.1.3+2010` (effective code `4010`;
`firstInstallTime` `2026-09-26 22:20:54`). T-193
synthetic backup/restore coverage is in place; physical acceptance of the
currency-repair detail UI remains open. Broader T-167c responsive-layout,
T-176 screen-inset, and T-179a key-recovery acceptance also remain open.

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
physical storage and cold-start impact remain unmeasured because the supported
phone is offline. Keep the published artifact above unchanged, and leave T-194
open until physical acceptance is recorded.

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
