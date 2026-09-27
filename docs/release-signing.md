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

The currently published download is `0.1.2+4` (set in `pubspec.yaml`), an
ARM64 APK for 64-bit ARM Android devices. Its size is 56,553,692 bytes
(56.55 MB decimal), and its SHA-256 is
`9965dcdae9b1011c5325a5f0c5a83f317d69d6fca38cacb5a007ec9e3c211746`.
The production signature was verified; install and launch passed on the
connected ARM64 phone. T-176 and T-179a physical-device acceptance remain open
because the full screen-inset and key-recovery scenarios were not exercised.
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
