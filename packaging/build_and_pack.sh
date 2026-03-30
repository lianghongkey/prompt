#!/usr/bin/env bash

set -e  # Exit on error

# Configuration
BUNDLE_IDENTIFIER='hk.eduhk.inputmethod.Prompt'
APP_VERSION='1.6.1'
INSTALL_LOCATION='/Library/Input Methods'
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGING_DIR="$PROJECT_ROOT/packaging"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Prompt.app"
PKG_NAME="Prompt.pkg"
DMG_NAME="Prompt-${APP_VERSION}.dmg"

echo "==> Building Prompt..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the app
cd "$PROJECT_ROOT"
xcodebuild \
    -project Prompt.xcodeproj \
    -scheme Prompt \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination 'platform=macOS' \
    build

# Find the built app
BUILT_APP=$(find "$BUILD_DIR/DerivedData/Build/Products" -name "$APP_NAME" -type d | head -n 1)

if [ ! -d "$BUILT_APP" ]; then
    echo "Error: Built app not found"
    exit 1
fi

echo "==> Found built app at: $BUILT_APP"

# Prepare packaging directory
cd "$PACKAGING_DIR"
rm -rf app
mkdir -p app
cp -R "$BUILT_APP" app/

echo "==> Creating PKG..."

# Create PKG
pkgbuild \
    --min-os-version 12.0 \
    --compression latest \
    --identifier "${BUNDLE_IDENTIFIER}" \
    --version "${APP_VERSION}" \
    --install-location "${INSTALL_LOCATION}" \
    --info PackageInfo \
    --component-plist PromptComponent.plist \
    --root "app" \
    --scripts "scripts" \
    "$BUILD_DIR/$PKG_NAME"

echo "==> Creating DMG..."

# Create temporary DMG directory
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy PKG to temp directory
cp "$BUILD_DIR/$PKG_NAME" "$DMG_TEMP/"

# Create DMG
hdiutil create \
    -volname "Prompt ${APP_VERSION}" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

# Clean up
rm -rf "$DMG_TEMP"
rm -rf "$PACKAGING_DIR/app"

echo ""
echo "==> Build complete!"
echo "PKG: $BUILD_DIR/$PKG_NAME"
echo "DMG: $BUILD_DIR/$DMG_NAME"
