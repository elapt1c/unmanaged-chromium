# What this can and cannot do

Written down because "anti-surveillance browser" attracts claims that are not true.
Each item names the mechanism, so you can verify rather than trust.

## It does defeat

**Chrome/Edge enterprise policy.** Chromium reads `HKLM\SOFTWARE\Policies\Chromium`
(on Windows) — a key no school deploys. Policies targeting `Google\Chrome` or
`Microsoft\Edge` are invisible to it. This is not a bypass, it is simply a different
product with a different policy namespace and no ADMX installed.

Includes, all of which are policy-driven in Chrome and absent here:

- forced or blocked extensions (`ExtensionInstallForcelist`, `...Blocklist`)
- locked search engine (`DefaultSearchProviderName`, `...SearchURL`, `...Enabled`)
- forced homepage / startup pages (`HomepageLocation`, `RestoreOnStartupURLs`)
- SafeSearch and YouTube restrictions
- `URLBlocklist` / `URLAllowlist` inside the browser itself
- the "managed by your organisation" notice

**Cloud management.** Chrome Enterprise can be enrolled by an MDM or by a cloud
policy token. Open-source Chromium snapshots carry no enrollment state, so there is
nothing to enrol and no cloud policy fetch to obey.

**Default-browser and first-run hijacking.** `--no-first-run` /
`--no-default-browser-check`, plus a profile that lives beside the binary.

**Self-updating.** `--disable-component-update` and no updater service. The binary
version is whatever you built; it will not change under you.

**Common telemetry.** `--no-pings`, `--disable-breakpad`,
`--disable-domain-reliability`, `--disable-background-networking`, and in
`preferences.json`: `disable_safe_browsing_uploads`, no metrics reporting, no
autofill server uploads.

## It does not defeat

**The network.** Your traffic still crosses their infrastructure. They can see the
IP addresses you connect to, the SNI of every TLS connection, and — unless you turn
on DNS-over-HTTPS — every hostname you resolve. DoH is enabled by default in this
profile, which hides *DNS names* from their resolver, not the SNI of the connection
that follows. To hide the destination itself you need a VPN or Tor; this project
ships neither.

**Certificate interception (on Windows).** Chromium on Windows and macOS uses the
operating system's root store. A school-installed root CA is trusted, and the browser
has no switch to ignore system roots. The available flag, `--ignore-certificate-errors`,
accepts every certificate error — it makes you *more* exposed, not less, and it is
deliberately not enabled by default here.

Ways to get a trust store the school does not control:

1. **Linux build of this project.** Chromium on Linux uses its own NSS database.
   The launcher points `NSSDB` at the portable profile, so the trust store travels
   with the folder and the school's Windows root CAs are simply absent.
2. **Firefox** with `security.enterprise_roots.enabled=false`, which keeps its own
   NSS store on every platform — including Windows.
3. A separate OS install or live USB, for the same reason as (1).

**Device management.** An MDM agent, a screen recorder, a keystroke logger, or an
extension running at OS level does not care which browser you launched. If the
machine is managed at the OS level, the browser is the wrong layer to fix it.

**Operating-system level filtering.** A DNS server you cannot change, a transparent
proxy, or a firewall rule blocks you regardless of browser flags. DoH helps only
against DNS-based filtering.

**Being seen using it.** A portable browser in a school lab is conspicuous. Nothing
technical changes that.

## Verifying the claims yourself

- `chrome://policy` — should be empty here, populated on managed Chrome.
- `chrome://version` — check the command line contains `--user-data-dir` pointing at
  the portable profile, and that the build is Chromium, not Chrome.
- `chrome://net-internals/#dns` — confirm the resolver is DoH once the profile loads.
- On Linux: `ls <profile>/NSSDB` — the trust store is there and is yours.
- Unplug the folder / delete it — nothing remains on the machine (no registry keys
  outside the browser's own hive, no services, no scheduled tasks).
