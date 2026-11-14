#!/usr/bin/env python3
"""Name the exact failure mode per site, and whether ECH can save it.

"Blocked" is five different faults with five different fixes:

  DNS-BLOCKED       resolver lies or returns nothing      -> DoH (already in the profile)
  TCP-BLOCKED       SYN nowhere, or reset                 -> only a relay helps
  SNI-BLOCKED       TCP connects, TLS dies mid-handshake  -> ECH if the site publishes it
  CERT-INTERCEPTED  handshake completes with a foreign CA -> relay; nothing in-browser
  OK                reachable as-is

The `ech` column is the part that answers "how many sites can we cover": it queries
the site's HTTPS RR (DNS type 65) over DoH and reports whether an Encrypted Client
Hello config is published. No ECH config means no way to hide that name, whatever
the browser does — only a relay changes the picture.

Run it on the network in question:

    python3 scripts/probe.py youtube.com reddit.com discord.com
    python3 scripts/probe.py --file hosts.txt --verbose

No third-party packages: stdlib sockets + ssl, DoH over plain HTTPS.
"""
import argparse
import base64
import json
import socket
import ssl
import struct
import sys
import time
import urllib.request

# Tried in order. Quad9's :5053 endpoint is unreachable from some networks
# (and returns nothing for type 65 rather than failing loudly), so Cloudflare
# first — it answers HTTPS RRs reliably.
DOH_RESOLVERS = [
    "https://cloudflare-dns.com/dns-query",
    "https://dns.quad9.net/dns-query",
]
TIMEOUT = 6.0
T_A, T_HTTPS = 1, 65


def _enc_name(name: str) -> bytes:
    out = b""
    for label in name.rstrip(".").split("."):
        out += bytes([len(label)]) + label.encode()
    return out + b"\x00"


def _dns_query(name: str, qtype: int) -> bytes:
    return (struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)
            + _enc_name(name) + struct.pack(">HH", qtype, 1))


def _doh(raw: bytes) -> bytes:
    last = None
    for base in DOH_RESOLVERS:
        url = f"{base}?dns={base64.urlsafe_b64encode(raw).decode().rstrip('=')}"
        req = urllib.request.Request(url, headers={"accept": "application/dns-message"})
        try:
            return urllib.request.urlopen(req, timeout=TIMEOUT).read()
        except Exception as e:
            last = e
    raise last


def _skip_name(buf: bytes, i: int) -> int:
    while i < len(buf) and buf[i] != 0:
        if buf[i] & 0xC0 == 0xC0:
            return i + 2
        i += buf[i] + 1
    return i + 1


def _records(raw: bytes):
    if len(raw) < 12:
        return []
    ancount = struct.unpack(">H", raw[6:8])[0]
    i = _skip_name(raw, 12) + 4
    out = []
    for _ in range(ancount):
        if i >= len(raw):
            break
        i = _skip_name(raw, i)
        if i + 10 > len(raw):
            break
        rtype, _cls, _ttl, rdlen = struct.unpack(">HHIH", raw[i:i + 10])
        i += 10
        out.append((rtype, raw[i:i + rdlen]))
        i += rdlen
    return out


def doh_a(host: str):
    try:
        return [socket.inet_ntoa(r) for t, r in _records(_doh(_dns_query(host, T_A)))
                if t == T_A and len(r) == 4], None
    except Exception as e:
        return None, f"doh-error: {type(e).__name__}"


def doh_ech(host: str):
    """(has_ech, human detail) from the HTTPS RR."""
    try:
        recs = _records(_doh(_dns_query(host, T_HTTPS)))
    except Exception as e:
        return None, f"https-rr: {type(e).__name__}"
    if not recs:
        return False, "no HTTPS RR"
    for rtype, rdata in recs:
        if rtype != T_HTTPS or len(rdata) < 3:
            continue
        i = _skip_name(rdata, 2)
        while i + 4 <= len(rdata):
            key, ln = struct.unpack(">HH", rdata[i:i + 4])
            i += 4
            val = rdata[i:i + ln]
            i += ln
            if key == 5:
                return (ln > 0), (f"ech {ln} bytes" if ln else "ech empty")
        return False, "HTTPS RR without ech"
    return False, "no HTTPS RR in answer"


def system_resolve(host: str):
    try:
        return sorted({ai[4][0] for ai in socket.getaddrinfo(host, 443, socket.AF_INET)}), None
    except Exception as e:
        return None, type(e).__name__


def tls_probe(ip: str, host: str):
    t0 = time.time()
    try:
        s = socket.create_connection((ip, 443), timeout=TIMEOUT)
    except Exception as e:
        return "tcp-fail", f"{type(e).__name__} after {time.time()-t0:.2f}s"
    ctx = ssl.create_default_context()
    try:
        with ctx.wrap_socket(s, server_hostname=host) as tls:
            cn = tls.getpeercert().get("subject", [[("CN", "?")]])[0][0][1]
            return "tls-ok", f"tls={tls.version()} cn={cn} cipher={tls.cipher()[0]}"
    except ssl.SSLCertVerificationError as e:
        return "tls-cert", f"verify: {e.verify_message or e}"
    except (ssl.SSLError, ConnectionResetError, BrokenPipeError, socket.timeout, OSError) as e:
        return "tls-fail", f"{type(e).__name__} mid-handshake"
    finally:
        try:
            s.close()
        except Exception:
            pass


def probe(host: str):
    row = {"host": host}
    sys_addrs, sys_err = system_resolve(host)
    doh_addrs, doh_err = doh_a(host)
    has_ech, ech_detail = doh_ech(host)

    row["system_dns"] = ",".join(sys_addrs) if sys_addrs else (sys_err or "none")
    row["doh_dns"] = ",".join(doh_addrs) if doh_addrs else (doh_err or "none")
    row["ech"] = has_ech
    row["ech_detail"] = ech_detail

    ip = (doh_addrs or sys_addrs or [None])[0]
    if not ip:
        row.update(verdict="DNS-BLOCKED", detail="no address from either resolver", fix="DoH")
        return row

    row["ip"] = ip
    state, detail = tls_probe(ip, host)
    row["detail"] = detail

    if state == "tcp-fail":
        row["verdict"], row["fix"] = "TCP-BLOCKED", "relay only"
    elif state == "tls-fail":
        row["verdict"] = "SNI-BLOCKED"
        row["fix"] = "ECH" if has_ech else "relay (no ECH config)"
    elif state == "tls-cert":
        row["verdict"], row["fix"] = "CERT-INTERCEPTED", "relay + Linux build"
    else:
        row["verdict"] = "OK"
        row["fix"] = "ECH-capable" if has_ech else "-"
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hosts", nargs="*")
    ap.add_argument("--file", help="one host per line")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true")
    a = ap.parse_args()

    hosts = list(a.hosts)
    if a.file:
        hosts += [l.strip() for l in open(a.file) if l.strip() and not l.startswith("#")]
    if not hosts:
        hosts = ["wordpress.com", "en.wordpress.com", "youtube.com", "www.google.com",
                 "reddit.com", "discord.com", "github.com", "wikipedia.org"]

    rows = [probe(h) for h in hosts]
    if a.json:
        print(json.dumps(rows, indent=2))
        return

    print(f"{'host':22} {'verdict':16} {'ech':4} {'ip':16} action")
    print("-" * 92)
    for r in rows:
        ech = {True: "yes", False: "no", None: "?"}[r["ech"]]
        print(f"{r['host'][:21]:22} {r['verdict']:16} {ech:4} {str(r.get('ip','-'))[:15]:16} {r.get('fix','')}")
        if a.verbose:
            print(f"    system dns: {r['system_dns']}")
            print(f"    doh dns   : {r['doh_dns']}")
            print(f"    https rr  : {r['ech_detail']}")
            print(f"    handshake : {r['detail']}")

    print(f"\nECH-capable: {sum(1 for r in rows if r['ech'])}/{len(rows)}")
    print("OK = fine as-is. SNI-BLOCKED with ech=yes -> ECH may fix it.")
    print("ech=no, TCP-BLOCKED or DNS-BLOCKED -> only a relay changes the outcome.")


if __name__ == "__main__":
    sys.exit(main())
