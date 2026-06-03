# XBLA ReXGlue Recomp — Retest Suite

A harness for static-recompiling several Xbox 360 XBLA titles with
[ReXGlue](https://github.com/Subarasheese/rexglue-sdk) and **re-testing them all
against each new ReXGlue release**.

ReXGlue is fast-moving and currently only fully works for Daytona USA (its
reference port). This repo keeps the per-game porting work (config, host shell,
function-boundary lists, stubs, patches, notes) in one place so that when a new
ReXGlue version ships you can rebuild everything and see what now works — without
redoing the scaffolding each time.

## No copyrighted data

This repo contains **only** recompilation scaffolding. No game executables,
extracted assets, or generated code are committed (see `.gitignore`). You must
supply your own legally-owned game packages; point `games.conf` at them.

## Layout

```
rexglue-sdk/            ReXGlue SDK — git submodule, tracks upstream (branch daytonaxbla)
tools/extract_game.py   STFS package -> default.xex extractor
games.conf              SDK path + per-game manifest + YOUR local package paths + last-known status
retest.sh               build + run + classify every game
games/<name>/
  config/*.toml         ReXGlue manifest + analysis config (incl. resolved function boundaries)
  project/src/          host shell: main.cpp, stubs.cpp, keyboard_driver.*
  project/CMakeLists.txt, CMakePresets.json
  ppc/                  PPC metadata headers
  patches/              diagnostic / fix patches (where applicable)
  NOTES.md              deep-dive findings for that title
  (assets/ extracted/ generated/ out/ are produced at retest time, git-ignored)
```

## Quick start

```sh
git submodule update --init --recursive          # fetch ReXGlue + its deps
# edit games.conf so each package_dir points at your local game's .../000D0000 folder
./retest.sh                                       # test all games
./retest.sh jetpac outrun                         # or a subset
```

First run builds the ReXGlue SDK once (~5 min); later runs reuse it.

## Retesting a new ReXGlue release

```sh
cd rexglue-sdk
git fetch && git checkout <new-tag-or-commit>     # or: git checkout daytonaxbla && git pull
git submodule update --init --recursive
cd ..
./retest.sh                                       # rebuilds SDK + all games, prints a status table
git add rexglue-sdk && git commit -m "bump ReXGlue to <ref>"   # pin the version you tested
```

The harness prints a summary like:

```
GAME           RESULT
daytona        RENDERS (N frames)
geometrywars   CRASH-NULL-CALL (recompiler bug)
jetpac         RENDERS-1-FRAME then stalls
outrun         NO-CRASH/HANG (no frames presented)
spacegiraffe   CRASH-NULL-CALL (recompiler bug)
```

## Status snapshot (see STATUS.md for detail)

| Game | Build | Result | Notes |
|------|-------|--------|-------|
| Daytona | ✅ | Plays (Vulkan flicker) | Reference port; ~9k lines bespoke |
| Geometry Wars | ✅ | Crash: `call 0x00000000` | Recompiler arg-marshaling bug |
| Space Giraffe | ✅ | Crash: `call 0x00000000` | Same recompiler bug |
| Jetpac Refuelled | ✅ (+XUsbcam stubs) | Boots + renders, then stalls | Closest to playable |
| OutRun | ✅ | Boots, hangs at shader pipeline | Heavy 3D engine |

The two crashes are a genuine **recompiler (codegen) correctness bug**, traced
with Xenia as ground truth — see `games/geometrywars/NOTES.md`. The HLE/kernel
layer and the Vulkan renderer are byte-identical to (working) Xenia, so those are
not the cause.
