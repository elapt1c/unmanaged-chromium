# Policy-free build

Everything in this repo except this directory packages an **upstream** Chromium
build. Upstream still contains the policy engine, and as documented in
`CANNOT-DO.md` it will obey `/etc/chromium/policies` or
`HKLM\SOFTWARE\Policies\Chromium` if anyone writes there. That is obscurity, not
immunity.

This directory is the fix: a source patch plus the build steps that remove the
capability instead of relying on nobody using it.

## The patch

`remove_policy_loaders.py` rewrites one function in
`components/policy/core/browser/browser_policy_connector.cc`:

```cc
std::vector<std::unique_ptr<PolicyLoaderInterface>>
BrowserPolicyConnector::CreatePolicyLoaders() {
  return std::vector<std::unique_ptr<PolicyLoaderInterface>>();
}
```

That function is the single choke point for policy on every platform. It returns
the platform loader — `PolicyLoaderLinux` reading `/etc/chromium/policies`,
`PolicyLoaderWin` reading the registry, `PolicyLoaderMac` reading managed
preferences. Everything above it (providers, machine and user cloud policy
managers, the `chrome://policy` page) is constructed from whatever it returns.

With no loaders: no registry read, no `/etc/chromium` read, no cloud fetch, no
forced extensions, no search-engine lock. Not "ignored" — never loaded.

## Building it

Requirements, honestly:

| Resource | Needed | Why |
|---|---|---|
| Disk | ~55-60 GB | ~30 GB checkout (`--no-history`) + ~25 GB `out/Release` |
| RAM | 16 GB+ | linking `chrome` peaks well above 8 GB |
| Cores | 8+ | 8 cores ≈ 4-8 h; 4 cores ≈ 10-14 h |
| Network | ~5 GB | depot_tools, source, prebuilt clang, sysroots |

```bash
# on the build host
export CHROMIUM_TAG=160.0.8158.0        # keep it in step with the packaged snapshots
./scripts/fetch-chromium.sh             # ~30 GB checkout at that tag
./scripts/build-policy-free.sh          # patch + gn + ninja
```

`build-policy-free.sh` applies the patch, configures a minimal release build and
refuses to continue if the patch did not apply — a build that silently keeps its
policy loaders is worse than no build.

## Verifying the result

```bash
# 1. the binary must contain no platform policy loader strings
strings out/Release/chrome | grep -c 'policies/managed'     # expect 0

# 2. and must refuse policy even when one is present
sudo mkdir -p /etc/chromium/policies/managed
echo '{"HomepageLocation":"http://policy-test.example/"}' \
  | sudo tee /etc/chromium/policies/managed/test.json
out/Release/chrome --no-sandbox chrome://policy    # must show no policies
```

Step 2 is exactly the test that fails on the packaged build today — see
`docs/proof-policy-applies.png`, where the same file forced
`DefaultSearchProviderEnabled=false`.

## Status

The patch is written and reviewed but **not yet compiled into a shipped binary**.
No machine available to this project currently has both the disk (~60 GB) and the
RAM headroom (16 GB+) to build it: the hosts are 4-core/4 GB, 4-core/15 GB/46 GB
free, and 8-core/15 GB/61 GB free — the last one would also be competing for RAM
with the game servers it hosts. Until that is resolved, releases from this repo
remain the upstream build with the limitations in `CANNOT-DO.md`.
