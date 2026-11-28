#!/bin/zsh
# Builds a Release app and wraps it in a DMG, signed with whatever identity is available.
#   scripts/make-dmg.sh                 ad-hoc signature (works on this Mac; others must right-click → Open once)
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=name scripts/make-dmg.sh    signed and notarized
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build.noindex/release"
APP="$BUILD/Build/Products/Release/Benz Mirror.app"
OUT="$ROOT/build.noindex/Benz-Mirror.dmg"
IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
xcodebuild -project BenzMirror.xcodeproj -scheme BenzMirror -configuration Release -derivedDataPath "$BUILD" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build | tail -3

codesign --force --deep --options runtime --sign "$IDENTITY" --entitlements Resources/BenzMirror.entitlements "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d)"
RW="$STAGE/rw.dmg"
trap 'rm -rf "$STAGE"' EXIT

# A volume left mounted from an earlier try would make Finder lay out the wrong disk.
for old in /Volumes/Benz\ Mirror*(N); do [[ -d "$old" ]] && hdiutil detach "$old" -force -quiet || true; done

# A read-write image first, so the window can be laid out (background, icon size and places) before it is compressed.
hdiutil create -size 80m -fs HFS+ -volname "Benz Mirror" -ov "$RW" >/dev/null
MOUNT="$(hdiutil attach "$RW" -nobrowse -noverify | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)"
cp -R "$APP" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"
mkdir "$MOUNT/.background"
cp "$ROOT/scripts/dmg/background.png" "$MOUNT/.background/background.png"

osascript <<OSA || echo "note: the window layout could not be set (Finder automation not allowed); the DMG still works"
tell application "Finder"
  tell disk "Benz Mirror"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to (POSIX file "$MOUNT/.background/background.png" as alias)
    set position of item "Benz Mirror.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach "$MOUNT" -quiet || { sleep 2; hdiutil detach "$MOUNT" -force -quiet; }
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

if [[ "$IDENTITY" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
fi
echo "Built $OUT"
