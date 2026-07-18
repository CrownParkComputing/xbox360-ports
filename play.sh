#!/usr/bin/env bash
# Launch a ported game for PLAY (no timeout, full license, all fixes).
#
#   ./play.sh soulcalibur
#   ./play.sh              # lists what's available
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ $# -lt 1 ]; then
  echo "Usage: ./play.sh <game>"
  echo "Available:"
  for d in games/*/project/out/build/linux-amd64/Release; do
    g=$(echo "$d" | cut -d/ -f2)
    [ -x "$d/$g" ] && echo "  $g"
  done
  exit 0
fi

NAME="$1"
shift  # remaining args pass through to the game binary
G="$ROOT/games/$NAME"
BIN="$G/project/out/build/linux-amd64/Release/$NAME"
[ -x "$BIN" ] || { echo "no binary for '$NAME' (run tools/newgame.sh / build first)"; exit 1; }

SDK_SRC="$(grep -E '^REXGLUE_SDK_SOURCE_DIR' "$G/project/out/build/linux-amd64/CMakeCache.txt" | cut -d= -f2-)"
SDK_OUT="${SDK_SRC:-/home/jon/development/xenon-native/repos/rexglue-sdk}/out/linux-amd64/Release"

# Don't let crash-loops fill the disk with cores.
ulimit -c 0

# Per-game workarounds. These are NOT preferences — each one works around a known SDK bug
# and should be deleted when that bug is fixed.
GAME_FLAGS=()
case "$NAME" in
  choplifter|ridgeracer)
    # The host render-target (FBO) path blows every lit/HDR surface out to red (blue
    # helicopter renders magenta). The pixel-shader-interlock path renders correctly.
    # Measured on the title screen: FBO mean R-G = +11.1, FSI = -8.2 (xenia-correct).
    # Remove once the FBO-path bug is fixed.
    GAME_FLAGS+=(--render_target_path_vulkan=fsi)
    ;;
  ridgeracer6)
    GAME_FLAGS+=(--render_target_path_vulkan=fsi)
    # 2D roadside trees flicker on NVIDIA: alpha-test precision sits exactly on the
    # leaf/background boundary and flip-flops frame-to-frame. Fuzzy alpha epsilon compares
    # with a 1e-3 window instead of exactly, which is stable. (Documented Xenia fix for
    # RR6 4E4D07D3; it existed only in the D3D12 translator, now ported to Vulkan/SPIR-V.)
    GAME_FLAGS+=(--use_fuzzy_alpha_epsilon=true)
    ;;
  jetpac)
    # No per-game flags needed. Jetpac's missing/black backgrounds were a NaN-in-tfetch
    # bug (stacked-texture Z became NaN, killing the sample); the NaN->0 guard is baked
    # into the SDK's SPIR-V translator, so it "just works" with the base flags.
    # Caveat: if a launch ever hangs trying to load a stale profile, remove
    #   ~/.local/share/jetpac/*/profile   (guest account blobs, safe to delete).
    :
    ;;
  splitsecond)
    # Multi-module title (launcher DEFAULT.XEX + SPLITSECOND1.DLL engine + SKIPPER.DLL
    # DLC loader). Boots and renders to the "PRESS B TO SKIP" content screen — past where
    # Xenia crashes (game-compat #2040). SKIPPER's DLC-load path (probing DLC:\SplitSecond0.dll
    # on an unmounted device) genuinely tries to load absent content and crashes if its
    # top-level query functions are recompiled; leaving them unrecompiled and returning null
    # ("no DLC") lets the game take its graceful skip path. That's what this flag does.
    GAME_FLAGS+=(--unregistered_function_nonfatal=true)
    ;;
  pgr3)
    # Project Gotham Racing 3 (retail disc launch title, 4D5307D1). Boots to race
    # loading screens in attract; batched bringup via unregistered_function_nonfatal.
    GAME_FLAGS+=(--unregistered_function_nonfatal=true)
    # NOTE: unlike ridgeracer/rr6/choplifter, PGR3 renders WORSE on FSI (heavy blocky
    # corruption on trees/crowd/barriers); the default FBO path draws the world cleanly.
    # Known FBO residue: black sky + noise on the car's reflection map (RT/cubemap class).
    # PGR3's present loop is unthrottled (1600+ FPS observed) and the presenter picks
    # IMMEDIATE mode -> tearing across the whole frame. Disallow immediate+mailbox so
    # the swapchain falls back to FIFO (real vsync), which also paces the guest loop.
    GAME_FLAGS+=(--vulkan_allow_present_mode_immediate=false)
    GAME_FLAGS+=(--vulkan_allow_present_mode_mailbox=false)
    # ...and the guest itself free-runs its present loop, so the UI thread samples the
    # output mid-overwrite (in-frame tearing even with FIFO). Cap guest swaps at the
    # title's native 30fps: a 60 cap on the ~46fps-capable sim gave an uneven 40-60
    # cadence that read as jitter; locked 30 matches the 360 cadence.
    GAME_FLAGS+=(--frame_limit=30)
    # Foliage/crowd/barrier alpha-tested surfaces show blocky per-frame corruption on
    # NVIDIA (same class as RR6's flickering trees): alpha compare sits exactly on the
    # cutout boundary. The fuzzy epsilon window stabilizes it.
    GAME_FLAGS+=(--use_fuzzy_alpha_epsilon=true)
    # Async pipeline compilation is on, but skipping incomplete frames DROPS whole
    # frames during each compile burst (291 new pipelines in one short race session)
    # — felt as "moves in stages" freezing. Present placeholder frames instead:
    # motion stays continuous, at the cost of brief object pop-in on new content.
    GAME_FLAGS+=(--vulkan_async_skip_incomplete_frames=false)
    # Perf: reuse unchanged texture/sampler descriptor sets across draws instead
    # of rewriting them for every one of the ~3-4k draws in a race frame
    # (smoke-verified in-race; default-off SDK cvar while it soaks).
    GAME_FLAGS+=(--vulkan_reuse_texture_descriptors=true)
    # "Disco windscreen" confetti: NOT alpha-to-mask (--alpha_to_mask=false changes
    # nothing, and there is no fixed-function a2c in the Vulkan pipeline) — the
    # dither is the game's own screen-door transparency; the defect is the colour
    # the kept lattice pixels get from the FBO RB path. Forensics in the RenderDoc
    # capture pgr3race_frame126545.rdc (glass draws are full-coverage, lattice is
    # in the depth buffer, one glass sub-draw outputs the car body colour).
    # [TEMP DIAG — remove when the glass-confetti bug is fixed] Arm an automatic
    # RenderDoc capture of the first dense race frame (and F12 for manual ones).
    # Captures land in games/pgr3/diag/.
    mkdir -p "$G/diag"
    export ENABLE_VULKAN_RENDERDOC_CAPTURE=1
    export REX_RENDERDOC_CAPTURE_DRAWS=400:120
    export REX_RENDERDOC_CAPTURE_PATH="$G/diag/pgr3"
    ;;
  raidenfighters)
    # Raiden Fighters Aces (retail disc, Success/Valcon 2009): menu + jj6/jj7/jj8.xex
    # game modules. Discovery is converged via batching, but stragglers on rarely-taken
    # paths still surface; degrade them to nulled calls instead of dying mid-play.
    GAME_FLAGS+=(--unregistered_function_nonfatal=true)
    ;;
esac

# Seed-save auto-install: some games (Ridge Racer 6) hard-block with a "corrupted save"
# message when their save is absent and never create one themselves. If the game ships a
# committed seed save and none is installed yet, drop it into the user data dir. rexglue does
# no signature check, so the save (originally made in Xenia) loads; the game re-saves over it.
SEED="$G/seedsave"
if [ -d "$SEED" ]; then
  for xuiddir in "$SEED"/*/; do
    [ -d "$xuiddir" ] || continue
    dest="$HOME/.local/share/$NAME/$(basename "$xuiddir")"
    if [ ! -d "$dest" ]; then
      mkdir -p "$(dirname "$dest")"
      cp -r "$xuiddir" "$dest"
      echo "installed seed save -> $dest"
    fi
  done
fi

# --headless=true: guest dialogs (Xbox Live sign-in prompts, message boxes, keyboard)
# auto-resolve with the default button instead of drawing the Xenia-style modal.
env GDK_BACKEND=x11 LD_LIBRARY_PATH="$SDK_OUT" \
  "$BIN" --game_data_root="$G/extracted" --gpu_plugin xenos \
  --gpu_allow_invalid_fetch_constants=true --audio_maxqframes=64 --license_mask=1 \
  --headless=true \
  ${GAME_FLAGS[@]+"${GAME_FLAGS[@]}"} \
  "$@"

# rexglue leaks a ~4.5GB /dev/shm segment if it dies uncleanly; sweep when idle.
pgrep -x "$NAME" >/dev/null 2>&1 || \
  find /dev/shm -maxdepth 1 -name 'xenia_memory_*' -user "$(id -un)" -delete 2>/dev/null
