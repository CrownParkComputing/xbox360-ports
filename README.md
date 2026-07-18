# Xbox 360 → Native Linux Ports (ReXGlue recomp suite)

This repository is a working suite for **statically recompiling Xbox 360 titles
into native Linux executables** using the
[ReXGlue SDK](https://github.com/CrownParkComputing/rexglue-sdk) — an
ahead-of-time PPC→C++ recompiler with an HLE kernel and Vulkan GPU backend,
heavily rooted in the foundations of the BSD-licensed
[Xenia](https://github.com/xenia-project) emulator.

Instead of interpreting or JIT-compiling PowerPC at runtime, each game's code is
translated to C++ once, compiled with your system compiler, and linked against
the ReXGlue runtime. The result is an ordinary Linux binary that reads the
game's own (user-supplied) data files. Several XBLA titles and retail-disc
titles boot, render, and play this way.

What lives here is the **per-title porting scaffolding**: recompiler configs and
resolved function boundaries, host-shell projects, per-game workaround flags,
bring-up tooling, and detailed engineering notes. It is the record of *how* each
title was brought up, reusable every time the SDK improves.

## Requirements — read this first

- **You must own the games.** This repo contains **no game code, no game
  assets, and no generated recompiler output** — only configuration and
  scaffolding (see the Legal section). You need your own legally-dumped game
  packages (XBLA STFS packages or retail disc dumps) to build anything runnable.
- Linux x86-64, Clang, CMake ≥ 3.21, Ninja, a Vulkan-capable GPU/driver.
- ~10 GB free disk per large title (generated C++ plus build tree), and
  /dev/shm large enough for a 4.5 GB guest-memory mapping.

## Quickstart

```sh
# 1. Clone both repos side by side (any location works)
git clone https://github.com/CrownParkComputing/xbox360-ports.git
git clone -b development https://github.com/CrownParkComputing/rexglue-sdk.git

# 2. Build the SDK once (multi-config Ninja; artifacts land in out/linux-amd64/Release)
cd rexglue-sdk
cmake --preset linux-amd64
cmake --build --preset linux-amd64-release

# 3. Point the suite at your SDK checkout
cd ../xbox360-ports
export SDK_SRC=/absolute/path/to/rexglue-sdk

# 4. Scaffold + first build of a new title from your own game package
tools/newgame.sh mygame mg "/path/to/YOUR GAME/.../000D0000"

# 5. Grind out unresolved-function fatals until the title converges
tools/bringup.sh mygame mg

# 6. Play
./play.sh mygame
```

`play.sh` launches a built title with the full set of known-good flags for it
(license unlock, headless dialog auto-resolve, plus any per-title workaround —
each one documented in the script with the bug it works around).

`tools/make_standalone.sh <game>` packages a built title into a self-contained
local bundle (binary + runtime libraries + launcher). Bundles contain
recompiled game code, so they are strictly for **local use** — the output
directory is never committed.

## Per-title status

Snapshot distilled from [STATUS.md](STATUS.md) (which has the full engineering
detail per title). "Playable" means user-verified gameplay.

| Title | Status | Notes |
|---|---|---|
| SoulCalibur | ✅ Playable | "Perfect" — guest setjmp/longjmp redirection was the key fix |
| SoulCalibur II HD | ✅ Playable | SPIR-V shader resync + load-shader pitch contract fix |
| Bubble Bobble Neo | ✅ Playable | setjmp/longjmp fix |
| Space Giraffe | ✅ Playable | setjmp/longjmp fix + thunk-cluster batch |
| Hydro Thunder Hurricane | ✅ Playable | White/untextured surfaces fixed by the `exp_adjust` fetch-constant fix |
| OutRun Online Arcade | ✅ Playable | Gear-change SFX loops (XMA one-shot completion bug) |
| Choplifter HD | ✅ Playable | Correct colours require the pixel-shader-interlock RT path (`play.sh` passes it) |
| Project Gotham Racing 3 (disc) | ✅ Plays | 30 fps pacing; known glass/reflection artifacts on the FBO RT path |
| Ridge Racer 6 (disc) | 🟡 Runs | FSI RT path + fuzzy alpha epsilon; seed save auto-installed |
| Ridge Racer (disc) | 🟡 Runs | FSI RT path for correct colours |
| Split/Second (disc) | 🟡 Boots | Multi-module (launcher + engine DLL); renders past where Xenia crashes |
| Raiden Fighters Aces (disc) | 🟡 Menu | Menu renders at 64 fps; per-game modules still in bring-up |
| Bionic Commando Rearmed | 🟡 Frozen | Renders but logic never advances (XamTask async-completion suspect) |
| Jetpac Refuelled | 🟡 Impaired | Boots + plays but some sprites invisible (one stacked-texture pixel shader) |
| SoulCalibur IV (disc) | ❌ Stalled | Codegen-clean, but stalls at the same point upstream Xenia does (compat #1128) |
| Daytona USA | ❌ Not working | Never presents a frame; needs from-scratch bring-up |
| Geometry Wars Evolved | ❌ Not working | Silent no-present stall |
| Trials HD | ❌ Not working | Black screen; XUI menus never load from .pak archives |
| Rainbow Islands | ❌ Not working | Bring-up grind incomplete |
| Bionic Commando Rearmed 2 | ❌ Not started | Scaffolded only |

## Repository layout

```
play.sh                 launch a built title with its known-good flags
tools/newgame.sh        scaffold a new title from the working template
tools/bringup.sh        iterative unresolved-function bring-up driver
tools/extract_game.py   STFS package -> default.xex + data extractor
tools/make_standalone.sh  package a built title into a local-use bundle
games/<name>/
  config/*.toml         ReXGlue manifest + recompiler config (function boundaries)
  project/              host shell: main.cpp, stubs, keyboard driver, CMake project
  ppc/                  PPC metadata headers
  NOTES.md              deep-dive findings for that title
  (assets/ extracted/ generated/ out/ appear at build time — git-ignored)
STATUS.md               full per-title engineering status + SDK bug history
```

## Troubleshooting

**Leaked 4.5 GB /dev/shm segments.** If a title dies uncleanly it leaves its
guest-memory mapping behind in `/dev/shm` (`xenia_memory_*`). `play.sh` sweeps
these when the game is not running; to clean up manually:

```sh
find /dev/shm -maxdepth 1 -name 'xenia_memory_*' -user "$(id -un)" -delete
```

**"GPU plugin not found" / no renderer.** The runtime loads its GPU backend
(`librexgpu-xenos.so`) at runtime — from the executable's own folder or from
`LD_LIBRARY_PATH`. `play.sh` sets `LD_LIBRARY_PATH` to the SDK's
`out/linux-amd64/Release`; if you launch a binary by hand, do the same or copy
the plugin (plus `librexruntime.so`) next to the executable.

**Wrong / red-shifted colours.** The Vulkan host render-target (FBO) path has a
known bug that blows lit/HDR surfaces out toward red on some titles. Passing
`--render_target_path_vulkan=fsi` (pixel shader interlock) renders correctly;
`play.sh` already does this for the affected titles.

**Launch hangs loading a stale profile.** Remove
`~/.local/share/<game>/*/profile` (guest account blobs, safe to delete).

## Legal

This project ships **no copyrighted material**: no game executables, no game
assets, no extracted data, and no recompiler-generated code derived from game
binaries. `.gitignore` enforces this — `assets/`, `extracted/`, `generated/`,
build outputs, packaged bundles, and capture artifacts are never committed.

To use this project you must supply content you own: dump your own games with
your own console. The resulting recompiled binaries and bundles embed
copyrighted game code and **must not be redistributed**.

This project is not affiliated with, nor endorsed by, Microsoft or Xbox. It
exists for educational, preservation, and interoperability purposes. All
trademarks and copyrights belong to their respective owners.
