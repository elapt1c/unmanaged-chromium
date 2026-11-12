#!/usr/bin/env python3
"""Patch a Chromium checkout so enterprise policy can never be applied.

Why this and not a flag: the policy engine is compiled into every Chromium build
and reads platform sources (registry on Windows, /etc/chromium on Linux, managed
preferences on macOS). No command-line switch disables it, so "unmanaged" is only
ever a statement about provisioning until the loader list is empty in source.

`BrowserPolicyConnector::CreatePolicyLoaders()` is the single choke point: it
returns the platform loader(s), and the whole policy stack — providers, the
machine/user cloud policy managers, and the `chrome://policy` UI — is built on top
of whatever it returns. Returning an empty vector means no loader exists, so no
policy value can enter the browser regardless of what an administrator writes.

Applied by scripts/build-policy-free.sh after checkout; idempotent.
"""
import re
import sys
from pathlib import Path

TARGET = Path("components/policy/core/browser/browser_policy_connector.cc")
NEEDLE = "BrowserPolicyConnector::CreatePolicyLoaders()"

STUB = """std::vector<std::unique_ptr<PolicyLoaderInterface>>
BrowserPolicyConnector::CreatePolicyLoaders() {
  // Policy-free build: return no loaders, so no policy source (registry,
  // /etc/chromium, managed preferences or cloud) can ever be consulted.
  // See patches/README.md.
  return std::vector<std::unique_ptr<PolicyLoaderInterface>>();
}"""


def main() -> int:
    if not TARGET.exists():
        print(f"error: {TARGET} not found — run from the Chromium src root", file=sys.stderr)
        return 1

    src = TARGET.read_text()
    if "Policy-free build" in src:
        print("already patched")
        return 0

    # Match from the function signature to the closing brace at column 0.
    pattern = re.compile(
        r"std::vector<std::unique_ptr<PolicyLoaderInterface>>\s*\n"
        r"BrowserPolicyConnector::CreatePolicyLoaders\(\)\s*\{.*?\n\}",
        re.S,
    )
    m = pattern.search(src)
    if not m:
        print(f"error: could not find {NEEDLE} — upstream layout changed", file=sys.stderr)
        return 1

    TARGET.write_text(src[: m.start()] + STUB + src[m.end():])

    # Fail loudly rather than silently shipping a browser that still obeys policy.
    out = TARGET.read_text()
    if "return std::vector<std::unique_ptr<PolicyLoaderInterface>>();" not in out:
        print("error: patch did not apply cleanly", file=sys.stderr)
        return 1

    print(f"patched {TARGET}: CreatePolicyLoaders() now returns no loaders")
    return 0


if __name__ == "__main__":
    sys.exit(main())
