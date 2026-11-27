#!/bin/zsh
# Builds a release "Benz Mirror.app" (ad-hoc signed, hardened runtime) into ./build.noindex (Spotlight does not index it).
# Needs XcodeGen (`brew install xcodegen`) only to regenerate BenzMirror.xcodeproj from project.yml.
set -euo pipefail

ROOT="${0:A:h:h}"
SERVER="scrcpy-server-v5.0.1"
cd "$ROOT"

[[ -f "Resources/$SERVER" ]] || "$ROOT/scripts/fetch-server.sh"
command -v xcodegen >/dev/null && "$ROOT/scripts/generate-project.sh" >/dev/null

xcodebuild -project BenzMirror.xcodeproj -scheme BenzMirror -configuration Release \
  -derivedDataPath build.noindex/DerivedData build | grep -E "error:|BUILD" || true

PRODUCT="build.noindex/DerivedData/Build/Products/Release/Benz Mirror.app"
[[ -d "$PRODUCT" ]] || { echo "Build failed" >&2; exit 1; }
rm -rf "build.noindex/Benz Mirror.app"
cp -R "$PRODUCT" "build.noindex/Benz Mirror.app"
codesign --verify --deep --strict "build.noindex/Benz Mirror.app"
echo "Built: $ROOT/build.noindex/Benz Mirror.app"
