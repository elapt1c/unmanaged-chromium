# unmanaged-chromium

A portable Chromium that **isn't managed in practice** — no policy is provisioned for
it, nothing enrols it, and none of the Chrome/Edge settings a school or employer
deploys reach it. Read the correction at the end of this section before treating that
as immunity. No enterprise policy, no
MDM enrollment, no forced extensions, no locked search engine, no "managed by your
organisation" banner. Runs from a folder or a USB stick, keeps its profile next to
itself, and leaves no services or updaters behind.

Built from **official Chromium snapshot builds** (`chromium-browser-snapshots`),
not Chrome — which matters, because that is the whole point (see below).

## Why Chromium and not Chrome

Enterprise policy on Windows lives in the registry under a product-specific key:

| Browser | Policy key it reads |
|---|---|
| Google Chrome | `HKLM\SOFTWARE\Policies\Google\Chrome` |
| Microsoft Edge | `HKLM\SOFTWARE\Policies\Microsoft\Edge` |
| **Chromium (this)** | `HKLM\SOFTWARE\Policies\Chromium` |

Schools deploy Chrome and Edge GPOs, and ship their ADMX templates. Nobody deploys
`Policies\Chromium`, and this build is not cloud-enrolled, so:

- `ExtensionInstallBlocklist` / `ExtensionInstallForcelist` → not applied
- `DefaultSearchProvider*` → not applied, your search engine stays yours
- `HomepageLocation`, `SafeSearches`, `URLBlocklist` → not applied
- "Managed by your organisation" → gone, because there is no policy to show

Check it yourself at any time: open `chrome://policy`. On a managed school Chrome
that page lists dozens of entries; here it is empty.

**The honest limit of that.** The policy engine is still compiled into this binary and
it still works. Writing `/etc/chromium/policies/managed/*.json` (Linux) or
`HKLM\SOFTWARE\Policies\Chromium` (Windows) *does* control this build — verified, with
a screenshot in `docs/proof-policy-applies.png`. What protects you is that nobody
provisions that namespace, not that the capability is absent. Making it truly absent
requires patching Chromium's policy loaders and building from source; see
`docs/CANNOT-DO.md`.

## What it deliberately does not do (read this)

**It does not hide you from the network.** Your school's Wi-Fi still sees which
IPs you connect to and which DNS names you ask for unless you turn on DNS-over-HTTPS
in the profile (see `docs/CANNOT-DO.md`). It does not defeat a proxy, a packet
filter, a device-management agent, or a teacher looking at the screen.

**It cannot isolate the certificate store on Windows.** Chromium on Windows reads
the OS root store through CryptoAPI, so a root CA your school installed machine-wide
is still trusted — there is no flag for this, and `--ignore-certificate-errors` is
not a fix (it trusts *everything*, including genuinely broken certs). For a trust
store the school cannot touch, run the Linux build: it uses its own NSS database
inside the portable profile.

Full list, with the exact mechanism for each limitation: `docs/CANNOT-DO.md`.

## Get it

Releases carry a prebuilt portable archive per platform:

- `unmanaged-chromium-windows-x64.zip` — unzip anywhere, run `launch.cmd`
- `unmanaged-chromium-linux-x64.tar.gz` — extract, run `./launch.sh`

No installer, no admin rights, no registry writes outside the browser's own
user hive, no auto-update. Delete the folder and it is gone.

## Build it yourself

```bash
# Linux / macOS
./scripts/build-linux.sh            # -> dist/unmanaged-chromium-linux-x64/

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
```

Both scripts pull the current snapshot number from
`chromium-browser-snapshots/<platform>/LAST_CHANGE`, download that revision, and
assemble the portable layout with the launcher, the hardened profile and the docs.
Nothing is vendored in git — the binaries come from Google's Chromium snapshot
bucket, so the repo stays small and the provenance is verifiable.

Pin a revision if you want reproducibility:

```bash
CHROMIUM_REV=1742910 ./scripts/build-linux.sh
```

## What the launcher sets

```
--user-data-dir=<profile next to the binary>   keep everything portable
--no-first-run --no-default-browser-check      no nags, no default-browser hijack
--disable-background-networking                no phone-home timers
--no-pings --disable-breakpad                  no crash/telemetry uploads
--disable-sync --disable-domain-reliability    no sync, no DR
--disable-component-update                     nothing silently upgrades itself
--disable-features=OptimizationHints,MediaRouter,InterestFeedContentSuggestions
```

Profile defaults live in `config/preferences.json` and are copied into the profile
on first run: DuckDuckGo, no third-party cookies, DoH enabled, WebRTC restricted to
proxied UDP, no Safe Browsing uploads, no autofill/telemetry reporting.

Edit `config/preferences.json` before building if you want different defaults.

## Censorship resistance

Encrypted Client Hello is enabled in the launcher, so SNI-based filtering has nothing
to match on for sites that publish ECH configs (most Cloudflare-fronted ones do). It
needs the DoH resolver from `config/preferences.json`, which is why both ship together.

Packet-level DPI evasion — GoodbyeDPI, zapret, byedpi — cannot live inside a browser:
it rewrites segments, TTLs or checksums, which needs a driver or root. Those are
documented as optional companions in `docs/DPI.md`, along with an honest account of
what neither approach beats (IP blocks, TLS interception, traffic analysis).

## Licence

Chromium itself is BSD-3-Clause; the snapshots are unmodified Google builds and
carry their own licence files inside the archive. The scripts and configuration in
this repo are MIT. This project ships no Google services, no branded Chrome, and no
modifications to the Chromium binary — it packages it with a launcher and defaults.

## Honest note

Using an unmanaged browser on a school or work machine may violate their acceptable
use policy, and that is a decision only you can make. Nothing here is illegal, but
"the browser didn't obey the policy" is not a defence if you agreed to one.
