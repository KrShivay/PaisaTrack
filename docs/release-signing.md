# Android Release Signing Guide

PaisaTrack enforces release signing security for production builds.

## Setting Up Release Signing

### Option A: Local Build with `keystore.properties`

1. Generate an Android release keystore:
   ```bash
   keytool -genkey -v -keystore android/paisatrack-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias paisatrack_release
   ```

2. Create a `keystore.properties` file in the project root or `android/` directory:
   ```properties
   storeFile=../android/paisatrack-release.jks
   storePassword=YOUR_STORE_PASSWORD
   keyAlias=paisatrack_release
   keyPassword=YOUR_KEY_PASSWORD
   ```

3. Build release bundle or APK:
   ```bash
   flutter build appbundle --release
   ```

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
