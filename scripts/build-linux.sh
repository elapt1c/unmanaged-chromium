#!/usr/bin/env bash
# Fetch an official Chromium snapshot and assemble the portable layout.
#
#   ./scripts/build-linux.sh              # latest snapshot
#   CHROMIUM_REV=1742910 ./scripts/build-linux.sh
#
# Output: dist/unmanaged-chromium-linux-x64/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="https://commondatastorage.googleapis.com/chromium-browser-snapshots/Linux_x64"
OUT="$REPO_ROOT/dist/unmanaged-chromium-linux-x64"

command -v curl >/dev/null || { echo "curl is required"; exit 1; }
command -v unzip >/dev/null || { echo "unzip is required"; exit 1; }

REV="${CHROMIUM_REV:-$(curl -fsSL "$BASE/LAST_CHANGE")}"
echo "==> revision $REV"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> downloading chrome-linux.zip"
curl -fL --retry 3 -o "$WORK/chrome-linux.zip" "$BASE/$REV/chrome-linux.zip"
unzip -q "$WORK/chrome-linux.zip" -d "$WORK"

rm -rf "$OUT"
mkdir -p "$OUT"
mv "$WORK/chrome-linux" "$OUT/chromium"

# Launcher, docs, defaults.
cp "$REPO_ROOT/scripts/launch.sh" "$OUT/launch.sh"
chmod +x "$OUT/launch.sh" "$OUT/chromium/chrome"
mkdir -p "$OUT/config"
cp "$REPO_ROOT/config/preferences.json" "$OUT/config/preferences.json"
cp "$REPO_ROOT/README.md" "$OUT/README.md"
cp "$REPO_ROOT/docs/CANNOT-DO.md" "$OUT/CANNOT-DO.md"
printf '%s\n' "$REV" > "$OUT/CHROMIUM_REV"

# Smoke test: the binary must run headless and report a version.
echo "==> smoke test"
V="$("$OUT/chromium/chrome" --version 2>&1 | head -1)" || {
  echo "binary failed to start:"; echo "$V"; exit 1; }
echo "    $V"

echo "==> done: $OUT"
du -sh "$OUT" 2>/dev/null || true
