#!/bin/bash
# Builds Vigil.app from source using the Swift toolchain (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Vigil.app"
ARCH="$(uname -m)"

echo "→ Building Vigil.app ($ARCH)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

swiftc \
  -O \
  -target "${ARCH}-apple-macosx13.0" \
  -framework AppKit -framework IOKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Vigil" \
  "$ROOT"/Sources/*.swift

# Ad-hoc signature so the app has a stable local identity.
codesign --force --sign - "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✓ Built $APP"
