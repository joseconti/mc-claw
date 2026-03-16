#!/bin/bash
# build-app.sh — Builds McClaw.app bundle with Sparkle support
#
# Usage:
#   ./scripts/build-app.sh              # Debug build
#   ./scripts/build-app.sh release      # Release build
#   ./scripts/build-app.sh release sign # Release + code sign
#
# After building, the .app is at: build/McClaw.app
# For distribution: zip -r McClaw-X.Y.Z.zip McClaw.app (from build/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SPM_DIR="$PROJECT_DIR/McClaw"

CONFIG="${1:-debug}"
SIGN="${2:-}"

echo "==> Building McClaw ($CONFIG)..."

# 1. Swift build
cd "$SPM_DIR"
if [ "$CONFIG" = "release" ]; then
    swift build -c release 2>&1
    BINARY="$SPM_DIR/.build/release/McClaw"
else
    swift build 2>&1
    BINARY="$SPM_DIR/.build/debug/McClaw"
fi

echo "==> Binary built at: $BINARY"

# 2. Create .app bundle structure
APP_DIR="$BUILD_DIR/McClaw.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

# 3. Copy binary
cp "$BINARY" "$MACOS/McClaw"

# 4. Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$CONTENTS/Info.plist"

# 4b. Copy app icon
ICON_FILE="$BUILD_DIR/McClaw.icns"
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$RESOURCES/McClaw.icns"
    echo "==> App icon embedded"
else
    echo "WARNING: McClaw.icns not found at $ICON_FILE"
    echo "         Run: iconutil -c icns build/McClaw.iconset -o build/McClaw.icns"
fi

# 4c. Copy BundledSkills
BUNDLED_SKILLS="$PROJECT_DIR/BundledSkills"
if [ -d "$BUNDLED_SKILLS" ]; then
    cp -R "$BUNDLED_SKILLS" "$RESOURCES/BundledSkills"
    # Clean up macOS metadata files
    find "$RESOURCES/BundledSkills" -name ".DS_Store" -delete 2>/dev/null || true
    find "$RESOURCES/BundledSkills" -name "__MACOSX" -exec rm -rf {} + 2>/dev/null || true
    SKILL_COUNT=$(find "$RESOURCES/BundledSkills" -maxdepth 1 -type d | wc -l | tr -d ' ')
    SKILL_COUNT=$((SKILL_COUNT - 1))
    echo "==> BundledSkills embedded ($SKILL_COUNT skills)"
else
    echo "WARNING: BundledSkills/ not found — no bundled skills will be included"
fi

# 4d. Copy localizations from SPM resource bundle
SPM_BUILD_DIR="$(dirname "$BINARY")"
SPM_RESOURCE_BUNDLE="$SPM_BUILD_DIR/McClaw_McClaw.bundle"
if [ -d "$SPM_RESOURCE_BUNDLE" ]; then
    LPROJ_COUNT=0
    for LPROJ in "$SPM_RESOURCE_BUNDLE"/*.lproj; do
        if [ -d "$LPROJ" ]; then
            cp -R "$LPROJ" "$RESOURCES/"
            LPROJ_COUNT=$((LPROJ_COUNT + 1))
        fi
    done
    # Copy the entire SPM resource bundle so Bundle.module resolves correctly
    cp -R "$SPM_RESOURCE_BUNDLE" "$RESOURCES/"
    echo "==> SPM resource bundle embedded"
    echo "==> Localizations copied: $LPROJ_COUNT .lproj directories"
else
    echo "WARNING: SPM resource bundle not found at $SPM_RESOURCE_BUNDLE"
    echo "         Localizations will not be included in the app bundle."
fi

# 5. Copy Sparkle.framework
SPARKLE_FW="$SPM_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$FRAMEWORKS/Sparkle.framework"
    echo "==> Sparkle.framework embedded"
else
    echo "WARNING: Sparkle.framework not found at $SPARKLE_FW"
    echo "         Auto-updates will not work without it."
fi

# 5b. Fix rpath so the binary finds Sparkle.framework in Frameworks/
install_name_tool -add_rpath @executable_path/../Frameworks "$MACOS/McClaw" 2>/dev/null || true

# 6. Code sign
# For notarization, Apple requires hardened runtime and signing inside-out
# (frameworks first, then binary, then .app bundle).
# Never use --deep as it doesn't handle nested frameworks correctly.
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
if [ "$SIGN" = "sign" ]; then
    echo "==> Code signing with: $IDENTITY (hardened runtime for notarization)"

    # 6a. Sign Sparkle.framework internals first
    if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
        # Sign XPC services and helpers inside Sparkle
        find "$FRAMEWORKS/Sparkle.framework" -type f -perm +111 -not -name ".*" | while read -r bin; do
            codesign --force --options runtime --sign "$IDENTITY" "$bin" 2>/dev/null || true
        done
        # Sign the framework bundle itself
        codesign --force --options runtime --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"
        echo "==> Sparkle.framework signed"
    fi

    # 6b. Sign the main binary
    codesign --force --options runtime --sign "$IDENTITY" "$MACOS/McClaw"
    echo "==> McClaw binary signed"

    # 6c. Sign the entire .app bundle
    codesign --force --options runtime --sign "$IDENTITY" "$APP_DIR"
    echo "==> McClaw.app signed"
else
    # Ad-hoc sign for local development (no notarization)
    codesign --force --sign - "$MACOS/McClaw"
    echo "==> Binary signed ad-hoc (development only)"
fi

echo "==> McClaw.app built at: $APP_DIR"
echo ""
echo "To create a distributable zip (MUST use ditto, not zip — zip corrupts code signatures):"
echo "  cd $BUILD_DIR && ditto -c -k --keepParent McClaw.app McClaw-\$(plutil -extract CFBundleShortVersionString raw $CONTENTS/Info.plist).zip"
