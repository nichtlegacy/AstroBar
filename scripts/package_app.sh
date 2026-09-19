#!/usr/bin/env bash
# Build AstroBar and assemble a runnable .app bundle (ad-hoc signed).
set -euo pipefail

CONF="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/version.env"

# Sparkle checks updates against this EdDSA public key; the private half lives in
# the login keychain and never leaves this machine. The feed is served straight
# from the repository so no extra hosting is needed.
FEED_URL="https://raw.githubusercontent.com/nichtlegacy/AstroBar/main/appcast.xml"
SPARKLE_PUBLIC_KEY="AUirFpMVvlCOQcflFJ5exmSeZmJ/CwevT5+vkHvQs/8="
SPARKLE_FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "› Building AstroBar ($CONF)…"
swift build -c "$CONF" --product AstroBar

BIN_DIR="$(swift build -c "$CONF" --product AstroBar --show-bin-path)"
APP="$ROOT/AstroBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/AstroBar" "$APP/Contents/MacOS/AstroBar"

# Sparkle ships as a dynamic framework; the executable finds it through the
# @executable_path/../Frameworks rpath set in Package.swift.
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "error: Sparkle framework missing at ${SPARKLE_FRAMEWORK}" >&2
    echo "hint: run 'swift package resolve' first" >&2
    exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

# Resources ship loose in Contents/Resources, the layout every Mac app uses.
# A download has no source tree and no .build directory to fall back on, so a
# missing resource here would be a broken icon on every machine except this one.
# Fail the build instead of publishing that.
cp "$ROOT/Sources/AstroBar/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ICON_KEY="    <key>CFBundleIconFile</key><string>AppIcon</string>"

for required in AppIcon.icns; do
    if [ ! -e "$APP/Contents/Resources/${required}" ]; then
        echo "error: bundled resource missing: Contents/Resources/${required}" >&2
        exit 1
    fi
done

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AstroBar</string>
    <key>CFBundleDisplayName</key><string>AstroBar</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>AstroBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
${ICON_KEY}
    <key>NSHumanReadableCopyright</key><string>© 2026 nichtlegacy. MIT License.</string>
    <key>AstroBarGitCommit</key><string>${GIT_COMMIT}</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing, inside out: nested code has to be signed before the bundle
# that contains it. Without an Apple Developer account there is no Developer ID
# and no notarization, so a downloaded build always meets Gatekeeper once.
# Sparkle verifies updates by EdDSA signature, which does not depend on Apple.
echo "› Signing (ad-hoc)…"
SPARKLE_IN_APP="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$SPARKLE_IN_APP/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign - --timestamp=none "$SPARKLE_IN_APP/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign - --timestamp=none "$SPARKLE_IN_APP/Versions/B/Updater.app"
codesign --force --sign - --timestamp=none "$SPARKLE_IN_APP/Versions/B/Autoupdate"
codesign --force --sign - --timestamp=none "$SPARKLE_IN_APP"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ Built $APP"
