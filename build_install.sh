#!/usr/bin/env bash

set -euo pipefail

BUILD_MODE="${1:-debug}"
DEVICE_ID="${2:-}"

case "$BUILD_MODE" in
  debug)
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
    FLUTTER_BUILD_ARGS=(apk --debug)
    ;;
  profile)
    APK_PATH="build/app/outputs/flutter-apk/app-profile.apk"
    FLUTTER_BUILD_ARGS=(apk --profile)
    ;;
  release)
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    FLUTTER_BUILD_ARGS=(apk --release)
    ;;
  *)
    echo "Invalid build mode: $BUILD_MODE"
    echo "Usage: $0 [debug|profile|release] [device-id]"
    exit 1
    ;;
esac

for command in flutter adb; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is not available in PATH."
    exit 1
  fi
done

if [[ ! -f "pubspec.yaml" ]]; then
  echo "pubspec.yaml not found."
  echo "Run this script from the Flutter project root."
  exit 1
fi

# Resolve target device.
if [[ -n "$DEVICE_ID" ]]; then
  ADB=(adb -s "$DEVICE_ID")
else
  CONNECTED_DEVICES=()

  while IFS= read -r device; do
    [[ -n "$device" ]] && CONNECTED_DEVICES+=("$device")
  done < <(
    adb devices |
      awk 'NR > 1 && $2 == "device" {print $1}'
  )

  DEVICE_COUNT="${#CONNECTED_DEVICES[@]}"

  if [[ "$DEVICE_COUNT" -eq 0 ]]; then
    echo "No authorized Android device found."
    echo "Connect a device and enable USB debugging."
    exit 1
  fi

  if [[ "$DEVICE_COUNT" -gt 1 ]]; then
    echo "Multiple devices found:"
    printf '  %s\n' "${CONNECTED_DEVICES[@]}"
    echo
    echo "Specify a device:"
    echo "$0 $BUILD_MODE <device-id>"
    exit 1
  fi

  DEVICE_ID="${CONNECTED_DEVICES[0]}"
  ADB=(adb -s "$DEVICE_ID")
fi

echo "Using device: $DEVICE_ID"

"${ADB[@]}" get-state >/dev/null

echo "Fetching dependencies..."
flutter pub get

echo "Building $BUILD_MODE APK..."
flutter build "${FLUTTER_BUILD_ARGS[@]}"

if [[ ! -f "$APK_PATH" ]]; then
  echo "APK not found at: $APK_PATH"
  exit 1
fi

get_package_name() {
  local apk_path="$1"
  local sdk_root
  local aapt_path

  if command -v apkanalyzer >/dev/null 2>&1; then
    apkanalyzer manifest application-id "$apk_path" 2>/dev/null
    return
  fi

  if command -v aapt >/dev/null 2>&1; then
    aapt dump badging "$apk_path" 2>/dev/null |
      awk -F"'" '/package: name=/{print $2; exit}'
    return
  fi

  sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"

  aapt_path="$(
    find "$sdk_root/build-tools" \
      -type f \
      -name aapt \
      2>/dev/null |
      sort -V |
      tail -1
  )"

  if [[ -n "$aapt_path" ]]; then
    "$aapt_path" dump badging "$apk_path" 2>/dev/null |
      awk -F"'" '/package: name=/{print $2; exit}'
  fi
}

echo "Installing APK..."

set +e
INSTALL_OUTPUT="$("${ADB[@]}" install -r -d "$APK_PATH" 2>&1)"
INSTALL_STATUS=$?
set -e

echo "$INSTALL_OUTPUT"

if [[ "$INSTALL_STATUS" -eq 0 ]]; then
  echo
  echo "Installed successfully: $APK_PATH"
  exit 0
fi

echo
echo "Update installation failed. Checking existing package..."

PACKAGE_NAME="$(get_package_name "$APK_PATH" || true)"

if [[ -z "$PACKAGE_NAME" ]]; then
  echo "Could not detect the APK package name."
  echo "Expected apkanalyzer or aapt in the Android SDK."
  exit 1
fi

echo "Detected package: $PACKAGE_NAME"

if "${ADB[@]}" shell pm list packages |
  tr -d '\r' |
  grep -Fqx "package:$PACKAGE_NAME"; then

  echo "Uninstalling existing app..."
  echo "Warning: local app data will be removed."

  "${ADB[@]}" uninstall "$PACKAGE_NAME"
else
  echo "The package is not currently installed."
  echo "The original installation error was unrelated to an existing app."
fi

echo "Installing APK again..."
"${ADB[@]}" install "$APK_PATH"

echo
echo "Installed successfully: $APK_PATH"