#!/bin/zsh
# Rebuilds Resources/ClipHelper.dex from Tools/ClipHelper/ClipHelper.java. Needs a JDK and the Android SDK (platform + build-tools).
# The .dex is committed, so building the app never needs the SDK; run this only after changing the Java file.
set -euo pipefail
ROOT="${0:A:h:h}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
PLATFORM=""
for candidate in $(ls -d "$SDK"/platforms/android-* | sort -V); do [[ -f "$candidate/android.jar" ]] && PLATFORM="$candidate"; done
[[ -n "$PLATFORM" ]] || { echo "No Android platform with android.jar found in $SDK"; exit 1; }
D8=""
for candidate in $(ls -d "$SDK"/build-tools/* | sort -V); do [[ -x "$candidate/d8" ]] && D8="$candidate/d8"; done
[[ -n "$D8" ]] || { echo "No d8 found in $SDK/build-tools"; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/classes"
javac -source 8 -target 8 -cp "$PLATFORM/android.jar" -d "$WORK/classes" "$ROOT/Tools/ClipHelper/ClipHelper.java" 2>&1 | grep -v "^warning\|^Note" || true
"$D8" --min-api 26 --output "$WORK" "$WORK"/classes/dev/benz/mirror/*.class
cp "$WORK/classes.dex" "$ROOT/Resources/ClipHelper.dex"
echo "Built Resources/ClipHelper.dex ($(wc -c < "$ROOT/Resources/ClipHelper.dex") bytes)"
