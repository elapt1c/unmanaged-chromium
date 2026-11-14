# DPI and the limits of "bake it into the browser"

Short version: **the part that works without admin rights is already in the
browser** (it just needs switching on), and **the part that needs packet tricks
cannot live inside Chromium at all** — it needs a kernel driver or root. Both
halves are described here so nobody expects the wrong thing.

## What can be built in — Encrypted Client Hello

SNI is the field in the TLS handshake that names the site you are visiting. It is
plaintext by design, which is what most school and ISP filters key on: they read
`ClientHello`, see `reddit.com`, and drop the connection. No amount of browser
hardening changes that, because the field has to be readable for SNI-based
routing to work.

ECH closes it. The handshake carries an encrypted inner ClientHello, and the outer
one names a shared Cloudflare front instead of your destination, so a passive DPI
box sees a generic connection. It is a browser feature, needs no privileges, and
is the only censorship-resistance mechanism that can genuinely be shipped in a
Chromium build.

This launcher enables it:

```
--enable-features=EncryptedClientHello
```

It only works if three things hold:

1. DNS-over-HTTPS is on — the ECH config is published as an HTTPS RR, which
   plain DNS cannot carry. Enabled in `config/preferences.json`
   (`dns_over_https.mode = secure`).
2. The site actually publishes ECH configs. Cloudflare-fronted sites mostly do;
   plenty of others do not.
3. The filter is not simply blocking by IP or by SNI allowlist for everything.
   ECH hides *which* site; it does not make a blocked IP reachable.

## What cannot be baked in — desync / fragmentation

GoodbyeDPI on Windows, zapret's `nfqws`/`winws` on Linux/Windows, and byedpi's
`ciadpi` all work by **rewriting packets**: splitting the ClientHello so the SNI
spans two TCP segments, sending a decoy segment with a bad checksum, or clamping
the TTL so the filter sees a different handshake than the server does.

That requires one of:

- a kernel driver (GoodbyeDPI uses WinDivert),
- a `NFQUEUE`/raw-socket hook (zapret, ciadpi), or
- Administrative/root rights to install it.

A browser cannot do it. Chromium writes into a normal socket; it does not control
segmentation, TTL, or checksums, and a build that tried to would be fighting the
kernel's TCP stack for every connection. On a school machine without admin rights,
none of these tools will run — which is exactly why the browser-level answer (ECH)
matters more than the packet-level one.

If you do have root on the machine you are on, they work well *alongside* this
build: run the desync tool, point it at port 443, and leave the browser alone.
Good pairings, in order of convenience:

| tool | platform | what it needs |
|---|---|---|
| byedpi (`ciadpi`) | Linux, Windows | root/admin for raw sockets |
| zapret (`nfqws`, `winws`) | Linux, Windows | root; `nfqueue` on Linux |
| GoodbyeDPI | Windows | admin (installs a WinDivert driver) |

None of them are vendored here: they are separately licensed, they update often,
and shipping a driver blob inside a browser package is a bad idea.

## Coverage, honestly

"What does SNI hiding cover" has a precise answer, and it is not "everything":

| mechanism | hides SNI from the filter | covers | needs |
|---|---|---|---|
| ECH | yes | sites that publish ECH configs — most Cloudflare-fronted ones | nothing |
| relay (`config/relay.txt`) | yes | **every** site | a proxy you control |
| QUIC / HTTP-3 | no, but many filters only parse TCP | sites offering h3 | nothing (already on) |
| DoH | no (hides DNS names only) | — | nothing |

The big Cloudflare-hosted web — Discord, Reddit, Medium, most forums, a large
share of smaller sites — publishes ECH. Google, Meta and Amazon do not, so ECH
does nothing for YouTube, Gmail or Instagram; for those, only a relay helps,
because there is no way to hide a name the server refuses to encrypt.

That is the whole reason the launcher reads `config/relay.txt`: put a SOCKS5
endpoint you control in it and every site goes through it; leave it empty and you
get ECH plus direct connections. Nothing "smart" can beat that arithmetic —
coverage is decided by whether the destination supports ECH, not by browser
configuration.

## What none of this does

- **IP-level blocking.** If the network drops packets to a destination address,
  ECH and desync both lose. Only a relay (VPN, Tor, or a proxy you control)
  helps, and that is a different project.
- **TLS interception.** If the machine trusts a school root CA, the connection is
  decrypted *after* the handshake — ECH does not protect content in that case.
  The Linux build with its own NSS store is the mitigation, as in `CANNOT-DO.md`.
- **Traffic analysis.** Packet sizes, timings and destinations still exist.
- **AUP.** Circumventing a network's filtering is usually an acceptable-use
  violation regardless of the tooling being legal. That call is yours.

## Trying it

With the packaged build, open a Cloudflare-fronted site that publishes ECH and
check `chrome://net-internals/#events` for `ECH` handshake results, or use
Cloudflare's own ECH test page. If the connection is being filtered by SNI you
will see a reset on the sites in question disappear once ECH is in use; if the
network is filtering by IP, nothing will change.
