#!/usr/bin/env bash
# Launch the portable Chromium with an unmanaged, self-contained profile.
#
# The profile (and, on Linux, the NSS certificate database) lives in ./profile
# next to this script — so the whole thing travels on a USB stick and leaves
# nothing behind on the host.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$HERE/profile"
BIN="$HERE/chromium/chrome"

[ -x "$BIN" ] || { echo "chromium binary missing: $BIN"; exit 1; }

mkdir -p "$PROFILE"

# Seed defaults once. Chromium rewrites this file as the user changes things, so
# never overwrite it after first run.
if [ ! -f "$PROFILE/Default/Preferences" ] && [ -f "$HERE/config/preferences.json" ]; then
  mkdir -p "$PROFILE/Default"
  cp "$HERE/config/preferences.json" "$PROFILE/Default/Preferences"
fi

# Isolated trust store: Chromium on Linux uses NSS, not the system bundle.
export NSSDB="$PROFILE/NSSDB"
export SSL_CERT_FILE="$PROFILE/NSSDB/cert9.db"
export SSL_CERT_DIR="$PROFILE/NSSDB"

# Keep runtime junk out of $HOME.
export XDG_CONFIG_HOME="$PROFILE/xdg/config"
export XDG_CACHE_HOME="$PROFILE/xdg/cache"
export XDG_DATA_HOME="$PROFILE/xdg/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"

exec "$BIN" \
  --user-data-dir="$PROFILE" \
  --no-first-run \
  --no-default-browser-check \
  --disable-background-networking \
  --disable-component-update \
  --disable-domain-reliability \
  --disable-sync \
  --no-pings \
  --disable-breakpad \
  --disable-client-side-phishing-detection \
  --metrics-recording-only \
  --disable-features=OptimizationHints,MediaRouter,InterestFeedContentSuggestions,Translate,AutofillServerCommunication \
  --enable-features=EncryptedClientHello \
  "$@"
