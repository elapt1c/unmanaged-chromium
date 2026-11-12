#!/usr/bin/env bash
# Assemble the portable Windows package on a Unix host.
#
# The Windows payload is just a zip of a Chromium build — nothing in it needs
# Windows to unpack and repackage, and a ubuntu runner is far quicker and more
# reliable at it than a Windows one. CI uses this; Windows users who prefer to
# build locally can use scripts/build-windows.ps1 instead.
#
# Output: dist/unmanaged-chromium-windows-x64/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="https://commondatastorage.googleapis.com/chromium-browser-snapshots/Win_x64"
OUT="$REPO_ROOT/dist/unmanaged-chromium-windows-x64"

command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v unzip >/dev/null || { echo "unzip is required"; exit 1; }

REV="${CHROMIUM_REV:-$(curl -fsSL "$BASE/LAST_CHANGE")}"
echo "==> revision $REV"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> downloading chrome-win.zip"
curl -fL --retry 3 -o "$WORK/chrome-win.zip" "$BASE/$REV/chrome-win.zip"
unzip -q "$WORK/chrome-win.zip" -d "$WORK"

rm -rf "$OUT"
mkdir -p "$OUT"
mv "$WORK/chrome-win" "$OUT/chromium"

# CRLF line endings: the launcher is a Windows batch file.
sed 's/$/\r/' "$REPO_ROOT/scripts/launch.cmd" > "$OUT/launch.cmd"
mkdir -p "$OUT/config"
cp "$REPO_ROOT/config/preferences.json" "$OUT/config/preferences.json"
cp "$REPO_ROOT/README.md" "$OUT/README.md"
cp "$REPO_ROOT/docs/CANNOT-DO.md" "$OUT/CANNOT-DO.md"
printf '%s\n' "$REV" > "$OUT/CHROMIUM_REV"

# Sanity: the payload must contain the binary and its version resource.
[ -f "$OUT/chromium/chrome.exe" ] || { echo "chrome.exe missing"; exit 1; }
echo "==> verify: chrome.exe $(stat -c%s "$OUT/chromium/chrome.exe") bytes"

echo "==> done: $OUT"
du -sh "$OUT" 2>/dev/null || true
