#!/usr/bin/env bash
# Re-test all XBLA recomp ports against the current ReXGlue SDK.
#
# For each game in games.conf:
#   extract STFS -> codegen -> build -> run (timeout) -> classify result.
# Nothing here ships copyrighted data; you supply your own game packages via
# the package_dir paths in games.conf.
#
# Usage:
#   ./retest.sh                 # test every game
#   ./retest.sh jetpac outrun   # test a subset
#   TIMEOUT=40 ./retest.sh      # longer run window
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
TIMEOUT="${TIMEOUT:-25}"
DISPLAY_ID="${DISPLAY_ID:-:1}"

# --- parse config ---
SDK_SRC=$(grep -E '^SDK_SRC=' games.conf | head -1 | cut -d= -f2-)
SDK_SRC=$(cd "$(dirname "$SDK_SRC")" 2>/dev/null && pwd)/$(basename "$SDK_SRC") 2>/dev/null || SDK_SRC="$ROOT/rexglue-sdk"
if [ ! -f "$SDK_SRC/CMakeLists.txt" ]; then
  echo "!! ReXGlue SDK not found at: $SDK_SRC"
  echo "   Init it:  git submodule update --init --recursive"
  echo "   Or set SDK_SRC in games.conf to an existing clone."
  exit 1
fi
SDK_OUT="$SDK_SRC/out/linux-amd64/Release"
REXGLUE="$SDK_OUT/rexglue"

want=("$@")
in_want() { [ ${#want[@]} -eq 0 ] && return 0; for w in "${want[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

declare -A RESULT
echo "=== ReXGlue retest @ $(git -C "$SDK_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown) ==="

while IFS='|' read -r name manifest pkgdir status; do
  case "$name" in ''|\#*|SDK_SRC=*) continue;; esac
  name=$(echo "$name" | xargs); manifest=$(echo "$manifest" | xargs); pkgdir=$(echo "$pkgdir" | xargs)
  in_want "$name" || continue
  G="$ROOT/games/$name"
  echo; echo "########## $name ##########"
  [ -d "$G" ] || { RESULT[$name]="NO-PORT-DIR"; echo "no games/$name"; continue; }

  # 1. extract (needs the user's local package)
  if [ ! -f "$G/assets/default.xex" ]; then
    if [ ! -d "$pkgdir" ]; then RESULT[$name]="NO-GAME-FILE"; echo "package_dir missing: $pkgdir"; continue; fi
    pkg=$(ls "$pkgdir"/* 2>/dev/null | head -1)
    python3 tools/extract_game.py "$pkg" --out "$G/extracted" --assets "$G/assets" >/tmp/rt_extract.log 2>&1 \
      || { RESULT[$name]="EXTRACT-FAIL"; tail -3 /tmp/rt_extract.log; continue; }
  fi

  # 2. codegen (rexglue segfaults AFTER 'Done.' — that's fine)
  ( cd "$G/config" && LD_LIBRARY_PATH="$SDK_OUT" "$REXGLUE" --force codegen "$manifest" ) >/tmp/rt_cg.log 2>&1
  grep -q "Done in" /tmp/rt_cg.log || { RESULT[$name]="CODEGEN-FAIL"; tail -4 /tmp/rt_cg.log; continue; }

  # 3. configure + build (force-recompile generated objs so regenerated code lands)
  BUILD="$G/project/out/build/linux-amd64"
  cmake --preset linux-amd64 -S "$G/project" -DREXGLUE_SDK_SOURCE_DIR="$SDK_SRC" >/tmp/rt_cfg.log 2>&1 \
    || { RESULT[$name]="CONFIGURE-FAIL"; tail -5 /tmp/rt_cfg.log; continue; }
  find "$BUILD/CMakeFiles/$name.dir" -path '*generated*' -name '*.o' -delete 2>/dev/null
  if ! cmake --build "$BUILD" --config Release --target "$name" >/tmp/rt_build.log 2>&1; then
    miss=$(grep -oE 'undefined reference to .__imp__[A-Za-z0-9_]+' /tmp/rt_build.log | grep -oE '__imp__[A-Za-z0-9_]+' | sort -u | tr '\n' ' ')
    RESULT[$name]="BUILD-FAIL${miss:+ (missing: $miss)}"; grep -iE 'error:' /tmp/rt_build.log | head -3; continue
  fi

  # 4. run + classify
  log="$G/run.log"; rm -f "$log"
  timeout "$TIMEOUT" env DISPLAY="$DISPLAY_ID" GDK_BACKEND=x11 LD_LIBRARY_PATH="$SDK_OUT" \
    "$BUILD/Release/$name" --game_data_root="$G/extracted" --log_file="$log" --log_level=debug \
    >/tmp/rt_run.log 2>&1 </dev/null
  addr=$(grep -oE 'unregistered function at guest address 0x[0-9A-Fa-f]+' "$log" 2>/dev/null | grep -oE '0x[0-9A-Fa-f]+' | tail -1)
  presents=$(grep -c 'PRESENT' "$log" 2>/dev/null)
  fatals=$(grep -c '\[FATAL\]\|\[critical\]' "$log" 2>/dev/null)
  if [ -n "$addr" ] && [ "$addr" = "0x00000000" ]; then RESULT[$name]="CRASH-NULL-CALL (recompiler bug)"
  elif [ -n "$addr" ]; then RESULT[$name]="CRASH-UNRESOLVED $addr (add to ${manifest%_*}_rexglue.toml)"
  elif [ "${presents:-0}" -gt 1 ]; then RESULT[$name]="RENDERS ($presents frames)"
  elif [ "${presents:-0}" -eq 1 ]; then RESULT[$name]="RENDERS-1-FRAME then stalls"
  elif [ "${fatals:-0}" -gt 0 ]; then RESULT[$name]="CRASH-OTHER ($(grep -m1 -oE '\[FATAL\].*' "$log" | cut -c1-60))"
  else RESULT[$name]="NO-CRASH/HANG (no frames presented)"; fi
  echo ">> $name: ${RESULT[$name]}"
done < games.conf

echo; echo "================ SUMMARY ================"
printf "%-14s %s\n" "GAME" "RESULT"
for k in "${!RESULT[@]}"; do printf "%-14s %s\n" "$k" "${RESULT[$k]}"; done | sort
