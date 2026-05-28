#!/bin/bash
# Sign, notarize, and staple Vigil.app for direct distribution.
# Prerequisites (one-time):
#   1. Apple Developer Program membership ($99/yr).
#   2. A "Developer ID Application" certificate in your login keychain
#      (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com).
#   3. A notarytool keychain profile:
#        xcrun notarytool store-credentials "vigil-notary" \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Usage: DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#        NOTARY_PROFILE="vigil-notary" ./scripts/sign-notarize.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Vigil.app"
DMG="$ROOT/build/Vigil.dmg"
: "${DEVELOPER_ID:?set DEVELOPER_ID to your 'Developer ID Application: …' identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to your notarytool keychain profile name}"

echo "→ Building fresh app"
bash "$ROOT/scripts/build.sh"

echo "→ Signing with Hardened Runtime"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/Resources/Vigil.entitlements" \
  --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "→ Building DMG"
rm -f "$DMG"
hdiutil create -volname "Vigil" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"

echo "→ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "→ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "✓ Signed + notarized: $DMG"
