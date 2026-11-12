#!/usr/bin/env bash
# Fetch a Chromium checkout for a policy-free build.
# Run on a build host with >=60 GB free and >=8 cores.
set -euo pipefail
export PATH="$HOME/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=1

mkdir -p "$HOME/src" && cd "$HOME/src"

if [ ! -d depot_tools ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$HOME/depot_tools"
fi

TAG="${CHROMIUM_TAG:-160.0.8158.0}"

if [ ! -d chromium/.git ]; then
  # --no-history keeps the checkout near 30 GB instead of ~90 GB.
  fetch --no-history --nohooks chromium
fi

cd chromium
git fetch --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" || true
git checkout -f "$TAG"
gclient sync -D --no-history --nohooks
echo "CHECKOUT_OK $(du -sh . | cut -f1)"
