#!/usr/bin/env python3
"""Patch a Chromium checkout so enterprise policy can never be applied.

Why this and not a flag: the policy engine is compiled into every Chromium build
and reads platform sources (registry on Windows, /etc/chromium on Linux, managed
preferences on macOS). No command-line switch disables it, so "unmanaged" is only
ever a statement about provisioning until the provider list is empty in source.

Where the choke point is depends on the Chromium version:

  160+:  chrome/browser/policy/chrome_browser_policy_connector.cc
         ChromeBrowserPolicyConnector::CreatePolicyProviders()
         — the only place the platform provider, the cloud policy manager, the
           command-line provider and the local test provider are assembled.
           Returning {} leaves policy with no source at all.

  older: components/policy/core/browser/browser_policy_connector.cc
         BrowserPolicyConnector::CreatePolicyLoaders()
         — the equivalent list of platform loaders.

Idempotent. Exits non-zero if neither anchor is found, because a build that
silently keeps its policy providers is worse than no build.
"""
import re
import sys
from pathlib import Path

MIRROR = Path("chrome/browser/policy/chrome_browser_policy_connector.cc")
LEGACY = Path("components/policy/core/browser/browser_policy_connector.cc")
MARKER = "Policy-free build"

STUB_160 = """std::vector<std::unique_ptr<policy::ConfigurationPolicyProvider>>
ChromeBrowserPolicyConnector::CreatePolicyProviders() {
  // Policy-free build: no platform provider (registry / /etc/chromium / managed
  // preferences), no cloud policy manager, no command-line provider, no local
  // test provider. Nothing can introduce a policy value. See patches/README.md.
  return std::vector<std::unique_ptr<policy::ConfigurationPolicyProvider>>();
}"""

STUB_LEGACY = """std::vector<std::unique_ptr<PolicyLoaderInterface>>
BrowserPolicyConnector::CreatePolicyLoaders() {
  // Policy-free build: return no loaders, so no policy source can be consulted.
  return std::vector<std::unique_ptr<PolicyLoaderInterface>>();
}"""

SIG_160 = re.compile(
    r"std::vector<std::unique_ptr<policy::ConfigurationPolicyProvider>>\s*\n"
    r"ChromeBrowserPolicyConnector::CreatePolicyProviders\(\)\s*\{"
)
SIG_LEGACY = re.compile(
    r"std::vector<std::unique_ptr<PolicyLoaderInterface>>\s*\n"
    r"BrowserPolicyConnector::CreatePolicyLoaders\(\)\s*\{"
)


def replace_function(src: str, sig: re.Pattern, stub: str):
    m = sig.search(src)
    if not m:
        return None
    end = src.find("\n}", m.end())
    if end == -1:
        return None
    return src[: m.start()] + stub + src[end + 2:]


def patch(path: Path, sig, stub, label: str) -> bool:
    if not path.exists():
        return False
    src = path.read_text()
    if MARKER in src:
        print(f"already patched: {path}")
        return True
    out = replace_function(src, sig, stub)
    if out is None:
        print(f"anchor not found in {path}", file=sys.stderr)
        return False
    path.write_text(out)
    if MARKER not in path.read_text():
        print(f"patch did not take in {path}", file=sys.stderr)
        return False
    print(f"patched ({label}): {path}")
    return True


def main() -> int:
    if not Path("components/policy").exists():
        print("error: run from the Chromium src root", file=sys.stderr)
        return 1
    if patch(MIRROR, SIG_160, STUB_160, "160+"):
        return 0
    if patch(LEGACY, SIG_LEGACY, STUB_LEGACY, "legacy"):
        return 0
    print("error: no known policy choke point found in this checkout", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
