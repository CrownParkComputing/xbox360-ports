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
