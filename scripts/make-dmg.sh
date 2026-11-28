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
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "Benz Mirror" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null

if [[ "$IDENTITY" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
fi
echo "Built $OUT"
