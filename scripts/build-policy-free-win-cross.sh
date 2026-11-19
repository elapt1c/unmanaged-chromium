#!/usr/bin/env bash
# Cross-compile the policy-free Windows build on a Linux host.
#
# Prerequisites (see docs/WINDOWS-BUILD.md):
#   - a Windows toolchain zip produced by depot_tools/win_toolchain/package_from_installed.py
#   - DEPOT_TOOLS_WIN_TOOLCHAIN_BASE_URL and GYP_MSVS_HASH_<hash> exported
#   - target_os = ['win'] in the gclient file, and gclient sync already re-run
#
# Run from the Chromium src root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -d components/policy ] || { echo "error: run from the Chromium src root"; exit 1; }
[ -n "${DEPOT_TOOLS_WIN_TOOLCHAIN_BASE_URL:-}" ] || {
  echo "error: DEPOT_TOOLS_WIN_TOOLCHAIN_BASE_URL is unset — see docs/WINDOWS-BUILD.md"; exit 1; }

echo "==> applying policy-free patch"
python3 "$REPO_ROOT/patches/remove_policy_loaders.py"

echo "==> gn gen (target_os=win)"
mkdir -p out/Win
cat > out/Win/args.gn <<'EOF'
target_os = "win"
target_cpu = "x64"
is_debug = false
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
use_thin_lto = false
enable_nacl = false
proprietary_codecs = false
ffmpeg_branding = "Chromium"
is_official_build = false
treat_warnings_as_errors = false
EOF
gn gen out/Win

echo "==> building chrome.exe (hours)"
autoninja -C out/Win chrome

BIN=out/Win/chrome.exe
[ -f "$BIN" ] || { echo "error: no chrome.exe produced"; exit 1; }
echo "==> built: $(ls -lh "$BIN" | awk '{print $5}')"

echo "==> packaging"
DEST="$REPO_ROOT/dist/unmanaged-chromium-policyfree-windows-x64"
rm -rf "$DEST"; mkdir -p "$DEST/chromium"
cp -r out/Win/. "$DEST/chromium/" 2>/dev/null || true
# Drop build-only artifacts that bloat the package (obj/ alone is several GB).
rm -rf "$DEST/chromium/obj" "$DEST/chromium/gen" "$DEST/chromium/clang_x64"* \
       "$DEST/chromium/siso"* "$DEST/chromium/.siso"* "$DEST/chromium/toolchain.ninja" \
       "$DEST/chromium/build.ninja" "$DEST/chromium/args.gn" 2>/dev/null || true
sed 's/$/\r/' "$REPO_ROOT/scripts/launch.cmd" > "$DEST/launch.cmd"
mkdir -p "$DEST/config"
cp "$REPO_ROOT/config/preferences.json" "$DEST/config/" 2>/dev/null || true
cp "$REPO_ROOT/config/relay.txt" "$DEST/config/" 2>/dev/null || true
cp "$REPO_ROOT/README.md" "$DEST/" 2>/dev/null || true
cp "$REPO_ROOT/docs/CANNOT-DO.md" "$DEST/" 2>/dev/null || true
cp "$REPO_ROOT/docs/DPI.md" "$DEST/" 2>/dev/null || true
echo "==> done: $DEST ($(du -sh "$DEST" | cut -f1))"
