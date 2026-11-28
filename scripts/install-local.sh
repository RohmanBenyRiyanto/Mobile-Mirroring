#!/bin/zsh
# Builds the Release app and installs it in /Applications, replacing the old copy, then opens it (for manual testing).
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$ROOT/build.noindex/release/Build/Products/Release/Benz Mirror.app"

cd "$ROOT"
xcodebuild -project BenzMirror.xcodeproj -scheme BenzMirror -configuration Release -derivedDataPath "$ROOT/build.noindex/release" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build | tail -1
codesign --force --deep --options runtime --sign - --entitlements Resources/BenzMirror.entitlements "$APP"

pkill -x BenzMirror 2>/dev/null || true
# Opening while the old copy is still shutting down would just wake that copy.
for _ in {1..20}; do pgrep -x BenzMirror >/dev/null || break; sleep 0.25; done
rm -rf "/Applications/Benz Mirror.app"
cp -R "$APP" "/Applications/Benz Mirror.app"
open "/Applications/Benz Mirror.app"
echo "Installed /Applications/Benz Mirror.app"
