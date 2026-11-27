#!/bin/zsh
# Downloads the official scrcpy server and refuses to keep it unless its SHA-256 matches the pinned value.
set -euo pipefail

VERSION="5.0.1"
EXPECTED="764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536"
ROOT="${0:A:h:h}"
TARGET="$ROOT/Resources/scrcpy-server-v$VERSION"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-server-v$VERSION" -o "$TMP/server"
ACTUAL="$(shasum -a 256 "$TMP/server" | cut -d' ' -f1)"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo "Checksum mismatch: $ACTUAL" >&2; exit 1; }

mkdir -p "$ROOT/Resources"
mv "$TMP/server" "$TARGET"
echo "OK: $TARGET"
