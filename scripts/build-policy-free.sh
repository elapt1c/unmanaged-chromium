#!/usr/bin/env bash
# Apply the policy-free patch and build Chromium.
#
# Run from a Chromium checkout root (the `src` directory produced by
# scripts/fetch-chromium.sh). Expect 4-14 h depending on cores, ~60 GB disk and
# 16 GB+ RAM while linking.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -f components/policy/core/browser/browser_policy_connector.cc ] || {
  echo "error: run this from the Chromium src root (no components/policy found)"; exit 1; }

echo "==> applying policy-free patch"
python3 "$REPO_ROOT/patches/remove_policy_loaders.py"

echo "==> configuring (minimal release, no debug info)"
mkdir -p out/Release
cat > out/Release/args.gn <<'EOF'
is_debug = false
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
use_thin_lto = false
enable_nacl = false
proprietary_codecs = false
ffmpeg_branding = "Chromium"
use_official_google_api_keys = false
enable_widevine = false
enable_linux_installer = false
treat_warnings_as_errors = false
EOF
gn gen out/Release

echo "==> building chrome (this is the long part)"
autoninja -C out/Release chrome

BIN="out/Release/chrome"
[ -x "$BIN" ] || { echo "error: build produced no binary"; exit 1; }

echo "==> verifying the policy loaders are gone"
if strings "$BIN" | grep -q 'policies/managed'; then
  echo "FAIL: binary still contains the Linux policy path — patch did not take"; exit 1
fi
echo "OK: no platform policy path in the binary"

echo "==> packaging"
DEST="$REPO_ROOT/dist/unmanaged-chromium-policyfree-linux-x64"
rm -rf "$DEST"; mkdir -p "$DEST"
cp -r out/Release/. "$DEST/chromium/"
cp "$REPO_ROOT/scripts/launch.sh" "$DEST/launch.sh"
mkdir -p "$DEST/config"
cp "$REPO_ROOT/config/preferences.json" "$DEST/config/preferences.json"
cp "$REPO_ROOT/README.md" "$DEST/README.md"
cp "$REPO_ROOT/docs/CANNOT-DO.md" "$DEST/CANNOT-DO.md"
chmod +x "$DEST/launch.sh" "$DEST/chromium/chrome"
echo "==> done: $DEST"
