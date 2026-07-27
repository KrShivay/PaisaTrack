#!/usr/bin/env bash
set -euo pipefail

# T-144a — Manifest scope & CI guard for Play SMS Exception.
# PaisaTrack qualifies under Play SMS Exception for READ_SMS / RECEIVE_SMS.
# SEND_SMS and WRITE_SMS are strictly prohibited.

TARGET_MANIFEST="${1:-android/app/src/main/AndroidManifest.xml}"

if [ ! -f "$TARGET_MANIFEST" ]; then
  echo "::error::Manifest file not found at: $TARGET_MANIFEST"
  exit 1
fi

echo "Checking manifest scope in $TARGET_MANIFEST..."

# Check for forbidden SMS permissions
FORBIDDEN=$(grep -iE 'permission\.(SEND_SMS|WRITE_SMS)' "$TARGET_MANIFEST" || true)

if [ -n "$FORBIDDEN" ]; then
  echo "::error::Forbidden SMS permission found in manifest ($TARGET_MANIFEST):"
  echo "$FORBIDDEN"
  echo "PaisaTrack Play Exception permits only READ_SMS and RECEIVE_SMS. SEND_SMS and WRITE_SMS are disallowed."
  exit 1
fi

echo "Manifest scope check passed cleanly (no SEND_SMS or WRITE_SMS found)."
