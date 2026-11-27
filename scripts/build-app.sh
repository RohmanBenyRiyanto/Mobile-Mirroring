#!/bin/zsh
# Builds a release "Benz Mirror.app" (ad-hoc signed, hardened runtime) into ./build.
# Needs XcodeGen (`brew install xcodegen`) only to regenerate BenzMirror.xcodeproj from project.yml.
set -euo pipefail

ROOT="${0:A:h:h}"
SERVER="scrcpy-server-v5.0.1"
cd "$ROOT"

[[ -f "Resources/$SERVER" ]] || "$ROOT/scripts/fetch-server.sh"
command -v xcodegen >/dev/null && xcodegen generate --quiet

xcodebuild -project BenzMirror.xcodeproj -scheme BenzMirror -configuration Release \
  -derivedDataPath build/DerivedData build | grep -E "error:|BUILD" || true

PRODUCT="build/DerivedData/Build/Products/Release/Benz Mirror.app"
[[ -d "$PRODUCT" ]] || { echo "Build failed" >&2; exit 1; }
rm -rf "build/Benz Mirror.app"
cp -R "$PRODUCT" "build/Benz Mirror.app"
codesign --verify --deep --strict "build/Benz Mirror.app"
echo "Built: $ROOT/build/Benz Mirror.app"
