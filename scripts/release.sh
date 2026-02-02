#!/bin/bash
# ABOUTME: Builds a signed, notarized Claide.app and packages it as a DMG.
# ABOUTME: Requires Developer ID certificate and notarytool credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="Claide"
ARCHIVE_PATH="$BUILD_DIR/Claide.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="Claide.app"

VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
DMG_NAME="Claide-${VERSION}.dmg"

echo "==> Claide $VERSION release build"
echo ""

# ── Regenerate Xcode project ────────────────────────────────────────
echo "==> Generating Xcode project..."
(cd "$PROJECT_DIR" && xcodegen generate --quiet)

# ── Clean & Archive ─────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release configuration)..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    2>&1 | tail -3

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive failed"
    exit 1
fi

# ── Export ───────────────────────────────────────────────────────────
echo "==> Exporting with Developer ID signing..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    2>&1 | tail -3

# ── Verify Signature ────────────────────────────────────────────────
echo "==> Verifying code signature..."
codesign --verify --deep --strict "$EXPORT_DIR/$APP_NAME"
echo "    Signing chain:"
codesign -dvv "$EXPORT_DIR/$APP_NAME" 2>&1 | grep "Authority" | sed 's/^/    /'

# ── Create DMG ──────────────────────────────────────────────────────
echo "==> Creating DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME"
hdiutil create \
    -volname "Claide" \
    -srcfolder "$EXPORT_DIR/$APP_NAME" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    > /dev/null

# ── Notarize ────────────────────────────────────────────────────────
echo "==> Notarizing (this may take a few minutes)..."

NOTARY_KEY_ID="${NOTARY_KEY_ID:-8P2FUGDM9K}"
NOTARY_ISSUER="${NOTARY_ISSUER:-69a6de8e-e98e-47e3-e053-5b8c7c11a4d1}"

# Look for .p8 key: env var, then ~/.keys/
if [[ -n "${NOTARY_KEY_PATH:-}" && -f "${NOTARY_KEY_PATH}" ]]; then
    KEY_PATH="$NOTARY_KEY_PATH"
elif [[ -f "$HOME/.keys/AuthKey_${NOTARY_KEY_ID}.p8" ]]; then
    KEY_PATH="$HOME/.keys/AuthKey_${NOTARY_KEY_ID}.p8"
else
    echo "ERROR: Cannot find AuthKey_${NOTARY_KEY_ID}.p8"
    echo "  Place it in ~/.keys/, or set NOTARY_KEY_PATH"
    echo ""
    echo "==> Un-notarized DMG at: $DMG_PATH"
    exit 0
fi

xcrun notarytool submit "$DMG_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --key "$KEY_PATH" \
    --wait

# ── Staple ──────────────────────────────────────────────────────────
echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# ── Done ────────────────────────────────────────────────────────────
echo ""
echo "==> Release ready:"
echo "    $DMG_PATH"
echo "    Version: $VERSION"
echo "    Signed, notarized, and stapled."
