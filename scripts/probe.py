#!/usr/bin/env python3
"""Find out *how* each site fails on this network — not just that it fails.

"Blocked" is four different problems with four different fixes:

  DNS-blocked     the resolver lies or returns nothing  -> DoH (already in the profile)
  TCP-blocked     SYN goes nowhere / is reset           -> only a relay helps
  SNI-blocked     TCP connects, TLS dies mid-handshake  -> ECH, or a relay
  cert-blocked    handshake completes with a foreign CA -> TLS interception; relay
  OK              handshake completes normally

This measures each layer separately, so you stop guessing which one you are up
against. Run it on the network in question:

    python3 scripts/probe.py wordpress.com youtube.com reddit.com ...
    python3 scripts/probe.py --file hosts.txt

No third-party packages: stdlib sockets + ssl, and DoH over plain HTTPS.
"""
import argparse
import json
import socket
import ssl
import sys
import urllib.request

DOH = "https://dns.quad9.net:5053/dns-query"
TIMEOUT = 6.0


def doh_resolve(host: str):
    """Resolve over DoH, bypassing the local resolver entirely."""
    import base64
    import struct

    # Minimal DNS query for A records, base64url-encoded as DoH requires.
    def enc_name(name):
        out = b""
        for label in name.rstrip(".").split("."):
            out += bytes([len(label)]) + label.encode()
        return out + b"\x00"

    q = struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0) + enc_name(host) + struct.pack(">HH", 1, 1)
    url = f"{DOH}?dns={base64.urlsafe_b64encode(q).decode().rstrip('=')}"
    req = urllib.request.Request(url, headers={"accept": "application/dns-message"})
    try:
        raw = urllib.request.urlopen(req, timeout=TIMEOUT).read()
    except Exception as e:
        return None, f"doh-error: {e}"

    # Walk the answer section for A records.
    if len(raw) < 12:
        return None, "doh-short"
    ancount = struct.unpack(">H", raw[6:8])[0]
    i = 12
    while i < len(raw) and raw[i] != 0:
        i += raw[i] + 1
    i += 5  # null label + type/class of the question
    addrs = []
    for _ in range(ancount):
        if i >= len(raw):
            break
        while i < len(raw) and raw[i] != 0:
            if raw[i] & 0xC0 == 0xC0:
                i += 2
                break
            i += raw[i] + 1
        else:
            i += 1
        if i + 10 > len(raw):
            break
        rtype, _rclass, _ttl, rdlen = struct.unpack(">HHIH", raw[i:i + 10])
        i += 10
        if rtype == 1 and rdlen == 4:
            addrs.append(socket.inet_ntoa(raw[i:i + 4]))
        i += rdlen
    return addrs, None


def system_resolve(host: str):
    try:
        return sorted({ai[4][0] for ai in socket.getaddrinfo(host, 443, socket.AF_INET)}), None
    except Exception as e:
        return None, str(e)


def tcp_probe(ip: str, host: str):
    """Connect, then complete a TLS handshake with SNI. Distinguishes TCP from TLS."""
    try:
        s = socket.create_connection((ip, 443), timeout=TIMEOUT)
    except Exception as e:
        return "tcp-fail", f"{type(e).__name__}: {e}"

    ctx = ssl.create_default_context()
    try:
        with ctx.wrap_socket(s, server_hostname=host) as tls:
            peer = tls.getpeercert()
            return "tls-ok", f"{tls.version()} {peer.get('subject', [[('CN', '?')]])[0][0][1]}"
    except ssl.SSLCertVerificationError as e:
        return "tls-cert", str(e.verify_message or e)
    except (ssl.SSLError, ConnectionResetError, BrokenPipeError, socket.timeout, OSError) as e:
        return "tls-fail", f"{type(e).__name__}: {e}"
    finally:
        try:
            s.close()
        except Exception:
            pass


def probe(host: str):
    row = {"host": host}
    sys_addrs, sys_err = system_resolve(host)
    doh_addrs, doh_err = doh_resolve(host)
    row["system_dns"] = ",".join(sys_addrs) if sys_addrs else (sys_err or "none")
    row["doh_dns"] = ",".join(doh_addrs) if doh_addrs else (doh_err or "none")

    ip = (doh_addrs or sys_addrs or [None])[0]
    if not ip:
        row["verdict"] = "DNS-BLOCKED"
        row["detail"] = "no address from either resolver"
        return row

    row["ip"] = ip
    state, detail = tcp_probe(ip, host)
    row["detail"] = detail
    row["verdict"] = {
        "tcp-fail": "TCP-BLOCKED",
        "tls-fail": "SNI-BLOCKED",
        "tls-cert": "CERT-INTERCEPTED",
        "tls-ok": "OK",
    }[state]
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hosts", nargs="*")
    ap.add_argument("--file", help="one host per line")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    hosts = list(a.hosts)
    if a.file:
        hosts += [l.strip() for l in open(a.file) if l.strip() and not l.startswith("#")]
    if not hosts:
        hosts = ["wordpress.com", "en.wordpress.com", "youtube.com", "www.google.com",
                 "reddit.com", "discord.com", "wikipedia.org"]

    rows = [probe(h) for h in hosts]
    if a.json:
        print(json.dumps(rows, indent=2))
        return

    print(f"{'host':28} {'verdict':16} {'ip':16} detail")
    print("-" * 100)
    for r in rows:
        print(f"{r['host'][:27]:28} {r['verdict']:16} {r.get('ip','-'):16} {r.get('detail','')[:44]}")

    print("\nLegend: OK = reachable as-is. SNI-BLOCKED needs ECH or a relay.")
    print("        TCP-BLOCKED / DNS-BLOCKED: only a relay changes the destination address.")
    print("        CERT-INTERCEPTED: something is decrypting TLS — a relay, not a flag.")


if __name__ == "__main__":
    sys.exit(main())
