#!/bin/zsh
# Builds MDM Inspector and assembles a double-clickable .app bundle.
# Usage: ./build_app.sh [--debug] [--version VERSION] [--build NUMBER]
set -euo pipefail

CONFIG=release
VERSION="${MDM_VERSION:-0.1}"
BUILD_NUMBER="${MDM_BUILD_NUMBER:-1}"
while (( $# > 0 )); do
    case "$1" in
        --debug) CONFIG=debug ;;
        --version) [[ $# -ge 2 ]] || { echo "--version requires a value" >&2; exit 2; }; VERSION="$2"; shift ;;
        --build) [[ $# -ge 2 ]] || { echo "--build requires a value" >&2; exit 2; }; BUILD_NUMBER="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
[[ "$BUILD_NUMBER" =~ '^[0-9]+$' ]] || { echo "build number must be numeric: $BUILD_NUMBER" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MDM Inspector"
BUNDLE_ID="com.local.mdminspector"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
cd "$ROOT"
swift build -c "$CONFIG" --product MDMInspector

# The product is named MDMInspector but lives in the MDMInspectorApp target,
# so SwiftPM writes it into a target-named directory.
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)/MDMInspectorApp"
BIN="$BIN_DIR/MDMInspector"
if [[ ! -x "$BIN" ]]; then
    # Fall back to the plain bin path (older SwiftPM layouts).
    BIN="$(swift build -c "$CONFIG" --show-bin-path)/MDMInspector"
fi
[[ -x "$BIN" ]] || { echo "build product missing at $BIN" >&2; ls "$(swift build -c "$CONFIG" --show-bin-path)" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MDMInspector"

# Copy icon if it exists
if [[ -f "$ROOT/Sources/MDMInspector/Resources/MDMInspector.icns" ]]; then
    cp "$ROOT/Sources/MDMInspector/Resources/MDMInspector.icns" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>MDMInspector</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key><string>MDMInspector</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>NSHumanReadableCopyright</key><string>Local-only log evidence viewer. No telemetry.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Log Archive</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key><array><string>com.apple.logarchive</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Sign AFTER the bundle is complete. Editing any file after this point
# invalidates the signature and Gatekeeper rejects the app, which is what
# made an earlier build unusable.
echo "==> codesigning (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/    /' || {
    echo "    ad-hoc signing failed; the app will still run locally" >&2
}

echo "==> verifying signature"
codesign --verify --deep --strict "$APP" || {
    echo "signature verification FAILED - do not distribute this build" >&2
    exit 1
}

echo "==> done: $APP"
echo "    open \"$APP\""
