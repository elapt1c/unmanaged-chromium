# Building a Windows binary (cross and native)

The policy-free Windows build needs the same source patch as Linux — the only
difference is the toolchain. Two routes exist; both are documented because the
choice depends on what hardware is available.

## Route A — cross-compile on Linux (official, needs one Windows touch)

Chromium **does** support building `chrome.exe` on a Linux host
(`docs/win_cross.md` in the checkout). What it does not do is ship Microsoft's
toolchain: MSVC and the Windows SDK are not redistributable in the form
`depot_tools` expects. So one Windows machine has to produce a toolchain zip
first — it does not have to run the build, and it does not need to be fast.

On that Windows box (Windows 10/11, Visual Studio 2019/2022 + Windows SDK, ~40 GB
installed):

```bat
cd path\to\depot_tools\win_toolchain
python package_from_installed.py 2022 -w 10.0.22621.0 --noarm
```

That writes `<hash>.zip` (a few GB). Copy it to the Linux build host and point
`depot_tools` at it:

```bash
export DEPOT_TOOLS_WIN_TOOLCHAIN_BASE_URL=<dir or http url holding the zip>
export GYP_MSVS_HASH_<hash>=<hash>
# then, in the checkout:
echo "target_os = ['win']" >> ../.gclient
gclient sync
```

Build:

```bash
gn gen out/Win --args='target_os="win" target_cpu="x64" is_debug=false
  is_component_build=false symbol_level=0 blink_symbol_level=0
  use_thin_lto=false enable_nacl=false proprietary_codecs=false
  ffmpeg_branding="Chromium" is_official_build=false'
autoninja -C out/Win chrome
```

Known gaps in cross builds, from Chromium's own doc: `js2gtest` targets are
omitted, `.asm` sources are stubbed so **Crashpad cannot report crashes**, and
NaCl is disabled. None of those affect the browser or the policy patch.

`scripts/build-policy-free-win-cross.sh` runs the patch + `gn` + `ninja` steps
once the toolchain and `target_os` are in place.

## Route B — native Windows build

A Windows 10/11 machine with Visual Studio 2022 and 150–250 GB free builds
directly (`fetch` → patch → `gn` → `autoninja`), no toolchain packaging step.
Slower to set up, fewer unknowns.

## What we have, honestly

- Linux policy-free build: **done** (`v1.1.0`), 729 MB binary, verified.
- Windows: **not built**. The cluster has one Windows VM, `ScambaitW8` — Windows 8,
  32 GB disk — which can neither install VS2022 nor run Chromium 160 (Chrome
  dropped Windows 8 at v110).
- Until a Windows 10/11 machine is available for either route, the Windows package
  on the releases page is upstream Chromium: unmanaged in practice (nothing
  provisions `Policies\Chromium`), but its policy engine is intact.
