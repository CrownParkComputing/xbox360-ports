#!/usr/bin/env bash
# make_gamepack.sh <game> [<game> ...]
#
# Builds a self-contained, legally-clean per-game distribution ZIP:
#   config + project scaffold + build/run script + README.
# It contains NO game code: no XEX, no extracted assets, no rexglue-generated
# recompiled source, no compiled binary. The end user supplies their own dumped
# game; the recompiled code is generated on THEIR machine. Every per-game fix
# flag (from play.sh) is baked into the pack's run script.
#
# Output: dist/<game>-rexglue-pack.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAY="$ROOT/play.sh"
DIST="$ROOT/dist"
mkdir -p "$DIST"

[ $# -ge 1 ] || { echo "usage: $0 <game> [<game> ...]"; exit 1; }

# Extract the GAME_FLAGS lines from play.sh's case block for a game.
extract_flags() {
  awk -v g="$1" '
    $0 ~ "^  "g"\\)" {inblk=1; next}
    inblk && /^  [a-z0-9]+\)/ {inblk=0}
    inblk && /^  esac/ {inblk=0}
    inblk && /GAME_FLAGS\+=/ {
      line=$0
      sub(/.*GAME_FLAGS\+=\(/, "", line); sub(/\).*/, "", line)
      gsub(/"/, "", line)
      print line
    }
  ' "$PLAY"
}

for GAME in "$@"; do
  GDIR="$ROOT/games/$GAME"
  [ -d "$GDIR/config" ] || { echo "!! no config for '$GAME', skipping"; continue; }
  PREFIX="$(ls "$GDIR/config" | sed -n 's/_manifest\.toml$//p' | head -1)"
  [ -n "$PREFIX" ] || { echo "!! no manifest for '$GAME', skipping"; continue; }

  PACK="$DIST/$GAME-pack"
  rm -rf "$PACK"; mkdir -p "$PACK"

  # Ship only OUR files (no game-derived content).
  cp -r "$GDIR/config" "$PACK/config"
  cp -r "$GDIR/ppc"    "$PACK/ppc" 2>/dev/null || true
  mkdir -p "$PACK/project"
  # project scaffold minus build output
  ( cd "$GDIR/project" && find . -type f -not -path './out/*' -print0 \
      | tar --null -cf - -T - ) | ( cd "$PACK/project" && tar -xf - )
  mkdir -p "$PACK/assets" "$PACK/gamedata"

  FLAGS="$(extract_flags "$GAME" | tr '\n' ' ')"

  cat > "$PACK/build_and_play.sh" <<EOF
#!/usr/bin/env bash
# Build and run $GAME (Xbox 360 -> native Linux via ReXGlue).
# You must supply your own legally-dumped game. NOTHING game-derived ships here.
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"

# 1. ReXGlue SDK: cloned + built at project/thirdparty/rexglue-sdk (see README).
SDK_SRC="\${SDK_SRC:-\$HERE/project/thirdparty/rexglue-sdk}"
SDK_OUT="\$SDK_SRC/out/linux-amd64/Release"
[ -x "\$SDK_OUT/rexglue" ] || { echo "ReXGlue SDK not built at \$SDK_OUT — see README step 1"; exit 1; }

# 2. Your game: extracted default.xex in assets/, extracted game data in gamedata/.
[ -f "\$HERE/assets/default.xex" ] || { echo "Put your extracted default.xex in \$HERE/assets/ — see README step 2"; exit 1; }

# 3. Recompile (generates native C++ from YOUR xex on YOUR machine) + build.
echo "== recompiling \$(basename $PREFIX)…"
( cd "\$HERE/config" && LD_LIBRARY_PATH="\$SDK_OUT" "\$SDK_OUT/rexglue" --force codegen "${PREFIX}_manifest.toml" )
BUILD="\$HERE/project/out/build/linux-amd64"
echo "== building $GAME…"
cmake --preset linux-amd64 -S "\$HERE/project" 2>/dev/null || cmake -S "\$HERE/project" -B "\$BUILD" -G "Ninja Multi-Config"
cmake --build "\$BUILD" --config Release --target $GAME

# 4. Launch with all per-game fixes applied.
BIN="\$BUILD/Release/$GAME"
echo "== launching $GAME…"
exec env GDK_BACKEND=x11 LD_LIBRARY_PATH="\$SDK_OUT" "\$BIN" \\
  --game_data_root="\$HERE/gamedata" --gpu_plugin xenos \\
  --gpu_allow_invalid_fetch_constants=true --audio_maxqframes=64 --license_mask=1 \\
  $FLAGS "\$@"
EOF
  chmod +x "$PACK/build_and_play.sh"

  cat > "$PACK/README.md" <<EOF
# $GAME — ReXGlue native Linux pack

Turn your **own legally-dumped** copy of this Xbox 360 title into a native Linux
game. This pack contains only the recompiler configuration and host scaffold —
**no game code or assets**. The game's code is recompiled from your XEX on your
own machine.

## Requirements
- Linux x86-64, Clang, CMake ≥ 3.21, Ninja, a Vulkan-capable GPU.
- Your own dumped game (the XEX + its data files).

## 1. Get the ReXGlue SDK
\`\`\`
git clone --recursive https://github.com/CrownParkComputing/rexglue-sdk.git \\
  project/thirdparty/rexglue-sdk
cd project/thirdparty/rexglue-sdk
cmake --preset linux-amd64 && cmake --build --preset linux-amd64-release
cd ../../..
\`\`\`
(Or set \`SDK_SRC=/path/to/your/rexglue-sdk\` if you already have one built.)

## 2. Add your game
- Put your extracted \`default.xex\` in \`assets/default.xex\`.
- Put the game's extracted data files in \`gamedata/\`.

## 3. Build and play
\`\`\`
./build_and_play.sh
\`\`\`
This recompiles your XEX, builds the native binary, and launches it with every
fix for this title already applied.

## Fixes applied for $GAME
$( [ -n "$FLAGS" ] && echo "\`$FLAGS\`" || echo "(standard launch flags only)" )

## Legal
No copyrighted game content is distributed in this pack. You must own the game.
EOF

  ( cd "$DIST" && zip -qr "$GAME-rexglue-pack.zip" "$GAME-pack" && rm -rf "$GAME-pack" )
  echo "== $GAME -> $DIST/$GAME-rexglue-pack.zip  (flags: ${FLAGS:-none})"
done
