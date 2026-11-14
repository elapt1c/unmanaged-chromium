#!/usr/bin/env bash
# Full policy-free Chromium build, run as a NON-ROOT user (depot_tools refuses
# to bootstrap as root). Resumable: each stage skips if its output exists.
set -euo pipefail

TAG="${CHROMIUM_TAG:-160.0.8158.0}"
H="$HOME"
SRC="$H/src"
export PATH="$H/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=1

log() { echo "=== [$(date -u +%H:%M:%S)] $*"; }

log "whoami: $(whoami) in $H"

log "stage 0: base packages"
if [ ! -f "$H/.base-deps" ]; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl python3 \
      python3-pip python3-venv xz-utils lsb-release file bzip2 pkg-config >/dev/null
  touch "$H/.base-deps"
fi

log "stage 1: depot_tools"
if [ ! -d "$H/depot_tools" ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$H/depot_tools"
fi
# Bootstrap depot_tools before anything else uses it.
( cd "$H/depot_tools" && ./ensure_bootstrap >/dev/null 2>&1 || true )

log "stage 2: fetch chromium $TAG"
mkdir -p "$SRC"
if [ ! -d "$SRC/chromium/.git" ] && [ ! -f "$SRC/.gclient" ]; then
  ( cd "$SRC" && fetch --no-history --nohooks chromium )
fi

# `fetch` is inconsistent about where it puts the tree: sometimes
# $SRC/chromium, sometimes $SRC with the checkout in $SRC/src. Detect rather
# than assume — assuming cost a completed 30 GB checkout on the first run.
if [ -d "$SRC/chromium/.git" ]; then
  cd "$SRC/chromium"
elif [ -f "$SRC/.gclient" ] && [ -d "$SRC/src" ]; then
  cd "$SRC/src"
else
  log "FAIL: no Chromium checkout found under $SRC"; exit 1
fi
log "checkout at $(pwd)";
git fetch --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" || true
git checkout -f "$TAG"
log "stage 3: gclient sync"
gclient sync -D --no-history --nohooks
log "checkout size: $(du -sh . | cut -f1)"

log "stage 4: build dependencies"
if [ ! -f "$H/.build-deps" ]; then
  sudo ./build/install-build-deps.sh --no-prompt --no-chromeos-fonts 2>&1 | tail -15
  touch "$H/.build-deps"
fi

log "stage 5: run hooks (clang, sysroots, ~2 GB)"
gclient runhooks 2>&1 | tail -5

log "stage 6: policy-free patch"
python3 "$H/unmanaged-chromium/patches/remove_policy_loaders.py"

log "stage 7: gn gen"
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

log "stage 8: build (hours)"
autoninja -C out/Release chrome 2>&1 | tail -40

log "stage 9: verify"
BIN=out/Release/chrome
[ -x "$BIN" ] || { log "FAIL: no binary produced"; exit 1; }
if strings "$BIN" | grep -q 'policies/managed'; then
  log "FAIL: binary still contains the platform policy path"; exit 1
fi
log "OK: no policy path string in the binary"
ls -la "$BIN"

log "stage 10: package"
DEST="$H/policyfree"
rm -rf "$DEST"; mkdir -p "$DEST/chromium"
cp -r out/Release/. "$DEST/chromium/"
cp "$H/unmanaged-chromium/scripts/launch.sh" "$DEST/launch.sh"
mkdir -p "$DEST/config"
cp "$H/unmanaged-chromium/config/preferences.json" "$DEST/config/preferences.json"
cp "$H/unmanaged-chromium/README.md" "$DEST/README.md"
cp "$H/unmanaged-chromium/docs/CANNOT-DO.md" "$DEST/CANNOT-DO.md"
chmod +x "$DEST/launch.sh" "$DEST/chromium/chrome"
tar -czf "$H/unmanaged-chromium-policyfree-linux-x64.tar.gz" -C "$H" policyfree
log "DONE: $(ls -lh "$H/unmanaged-chromium-policyfree-linux-x64.tar.gz")"
