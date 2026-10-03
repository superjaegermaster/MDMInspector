#!/bin/zsh
# Packages the built .app into a distributable .pkg and .dmg.
#
# Order matters: the app must be fully assembled and signed BEFORE it is
# packaged. Modifying the bundle afterwards (e.g. editing Info.plist to add an
# icon key) invalidates the signature, and Gatekeeper then refuses to launch
# it on any machine. If build_app.sh has not verified the signature, this
# script refuses to run.
#
# Usage: ./make_installer.sh [--no-dmg]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MDM Inspector"
BUNDLE_ID="com.local.mdminspector"
VERSION="0.1"
APP="$ROOT/build/$APP_NAME.app"
OUT="$ROOT/build/dist"

[[ -d "$APP" ]] || { echo "no app at $APP - run ./build_app.sh first" >&2; exit 1; }

# Gate on a valid signature rather than discovering the problem after shipping.
codesign --verify --deep --strict "$APP" 2>/dev/null || {
    echo "app signature is invalid - refusing to package" >&2
    echo "run ./build_app.sh, then try again" >&2
    exit 1
}
echo "==> app signature verified"

rm -rf "$OUT"
mkdir -p "$OUT"
STAGE="$OUT/pkgroot"
mkdir -p "$STAGE/Applications"
cp -R "$APP" "$STAGE/Applications/"

echo "==> building .pkg"
pkgbuild \
    --root "$STAGE" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    "$OUT/$APP_NAME-$VERSION.pkg" 2>&1 | sed 's/^/    /'

if [[ "${1:-}" != "--no-dmg" ]]; then
    echo "==> building .dmg"
    DMG_SRC="$OUT/dmgsrc"
    mkdir -p "$DMG_SRC"
    cp -R "$APP" "$DMG_SRC/"
    ln -s /Applications "$DMG_SRC/Applications"

    # Background so the volume is not just an app on a blank page.
    python3 - <<'PY' 2>/dev/null || true
from PIL import Image, ImageDraw
img = Image.new("RGB", (660, 400), (32, 34, 44))
d = ImageDraw.Draw(img)
d.rounded_rectangle([40, 40, 300, 220], radius=12, fill=(56, 90, 165))
d.rounded_rectangle([360, 170, 620, 360], radius=12, fill=(245, 245, 248))
d.text((46, 54), "MDM Inspector", fill=(255, 255, 255))
img.save("/tmp/.dmgbg.png")
PY

    hdiutil create \
        -srcfolder "$DMG_SRC" \
        -volname "$APP_NAME" \
        -fs HFS+ \
        -format UDZO \
        -quiet \
        "$OUT/$APP_NAME-$VERSION.dmg"
    rm -f "$DMG_SRC/Applications"
    rm -rf "$DMG_SRC"
fi

rm -rf "$STAGE"

echo
echo "==> built:"
for f in "$OUT"/*.pkg "$OUT"/*.dmg; do
    [[ -e "$f" ]] || continue
    printf '    %-40s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done
echo
echo "Unsigned and arm64-only. See README 'Distribution' before sharing."