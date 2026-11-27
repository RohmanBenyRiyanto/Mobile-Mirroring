#!/bin/zsh
# Regenerates BenzMirror.xcodeproj from project.yml, and tells Xcode to keep its build output in build.noindex.
# Spotlight skips folders ending in .noindex, so built copies of the app stay out of Cmd+Space results.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
xcodegen generate --quiet

SETTINGS="BenzMirror.xcodeproj/project.xcworkspace/xcshareddata"
mkdir -p "$SETTINGS"
cat > "$SETTINGS/WorkspaceSettings.xcsettings" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BuildLocationStyle</key>
	<string>UseAppPreferences</string>
	<key>CustomBuildLocationType</key>
	<string>RelativeToWorkspace</string>
	<key>DerivedDataCustomLocation</key>
	<string>build.noindex/DerivedData</string>
	<key>DerivedDataLocationStyle</key>
	<string>WorkspaceRelativePath</string>
</dict>
</plist>
PLIST
echo "Generated BenzMirror.xcodeproj (build output: build.noindex/)"
