#!/usr/bin/env bash
# Iterative unresolved-function bringup driver for an xbla-recomp-suite game.
#
#   run -> read [FATAL] "unregistered function at guest address 0xN"
#       -> append 0xN to <prefix>_rexglue.toml [functions] -> codegen -> build -> repeat
#
# Lives in the repo (NOT /tmp) so it survives a reboot.
#
# Usage:
#   tools/bringup.sh hydrothunder ht            # loop until it renders or gets stuck
#   RUN_ONLY=1 tools/bringup.sh hydrothunder ht # just run + classify, no codegen/build
#   MAX_ITERS=8 SECS=30 tools/bringup.sh hydrothunder ht
set -u

NAME="${1:-hydrothunder}"
PREFIX="${2:-ht}"
SECS="${SECS:-25}"
MAX_ITERS="${MAX_ITERS:-6}"
RUN_ONLY="${RUN_ONLY:-0}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT/games/$NAME"
BUILD="$G/project/out/build/linux-amd64"
BIN="$BUILD/Release/$NAME"
TOML="$G/config/${PREFIX}_rexglue.toml"
MANIFEST="$G/config/${PREFIX}_manifest.toml"

# The official SDK (NOT the suite's daytonaxbla fork) — this is what the HT/OutRun/jetpac
# builds are configured against; read it back from the build cache so we can't drift.
SDK_SRC="$(grep -E '^REXGLUE_SDK_SOURCE_DIR' "$BUILD/CMakeCache.txt" 2>/dev/null | cut -d= -f2-)"
SDK_SRC="${SDK_SRC:-/home/jon/development/xenon-native/repos/rexglue-sdk}"
SDK_OUT="$SDK_SRC/out/linux-amd64/Release"

LOGDIR="$G/logs"; mkdir -p "$LOGDIR"

# A crashing guest dumps an 18MB+ core EVERY iteration and spawns a ~1G systemd-coredump
# process to compress it. In a tight bringup loop that storm is what wedged the box before.
ulimit -c 0

run_once() {
  local log="$LOGDIR/run.log"
  rm -f "$log"
  # --gpu_allow_invalid_fetch_constants: HT tags many texture fetch constants with the
  # "invalid" type. Without this, BindingInfoFromFetchConstant bails early leaving the
  # texture key invalid -> nothing bound -> untextured (BLACK) boats/geometry.
  #
  # --audio_maxqframes=64: the 8-frame default starves the audio worker, which then falls
  # into its 500ms fallback Sleep (audio_system.cpp:164) with the guest frame loop waiting
  # on it -> a 250-500ms freeze every ~3s. Measured: worst frame 528ms -> 38ms, and every
  # hitch over 50ms disappears. Verify with tools/framepacing.py on the run log.
  # --license_mask=1: XBLA titles run as TRIAL without a license grant (Xenia uses the
  # same flag); 1 = first/full license so the full game unlocks.
  # --headless=true: guest dialogs (Xbox Live sign-in prompts, message boxes, keyboard)
  # auto-resolve with the default button instead of drawing the Xenia-style modal.
  timeout -k 5 "$SECS" env DISPLAY="${DISPLAY:-:1}" GDK_BACKEND=x11 LD_LIBRARY_PATH="$SDK_OUT" \
    "$BIN" --game_data_root="$G/extracted" --gpu_plugin xenos \
    --gpu_allow_invalid_fetch_constants=true --audio_maxqframes=64 --license_mask=1 \
    --headless=true \
    --log_file="$log" --log_level=debug >"$LOGDIR/stdout.log" 2>&1 </dev/null
  # The -k hard-kill skips the game's shm cleanup: each killed run orphans a ~4.5GB
  # /dev/shm/xenia_memory_* segment, and a full /dev/shm makes EVERY game SIGBUS at
  # startup (looks exactly like a code regression). Sweep when no game is running.
  pgrep -x "$NAME" >/dev/null 2>&1 || \
    find /dev/shm -maxdepth 1 -name 'xenia_memory_*' -user "$(id -un)" -delete 2>/dev/null
  echo "$log"
}

classify() {
  local log="$1"
  local addr presents fatals
  addr=$( { grep -oE 'unregistered function at guest address 0x[0-9A-Fa-f]+' "$log" 2>/dev/null; \
            grep -oE 'Unresolved (call|branch) from 0x[0-9A-Fa-f]+ to 0x[0-9A-Fa-f]+' "$log" 2>/dev/null \
              | grep -oE 'to 0x[0-9A-Fa-f]+'; } \
         | grep -oE '0x[0-9A-Fa-f]+' | tail -1)
  presents=$(grep -c 'PRESENT' "$log" 2>/dev/null)
  fatals=$(grep -c '\[FATAL\]\|\[critical\]' "$log" 2>/dev/null)
  echo "presents=${presents:-0} fatals=${fatals:-0} unresolved=${addr:-none}"
}

last_addr() {
  grep -oE 'unregistered function at guest address 0x[0-9A-Fa-f]+' "$1" 2>/dev/null \
    | grep -oE '0x[0-9A-Fa-f]+' | tail -1
}

# All unresolved addrs seen this run (a big game hits different ones per execution path,
# so batch them all in rather than one-per-rebuild).
all_addrs() {
  { grep -oE 'unregistered function at guest address 0x[0-9A-Fa-f]+' "$1" 2>/dev/null; \
    grep -oE 'Unresolved (call|branch) from 0x[0-9A-Fa-f]+ to 0x[0-9A-Fa-f]+' "$1" 2>/dev/null \
      | grep -oE 'to 0x[0-9A-Fa-f]+'; } \
    | grep -oE '0x[0-9A-Fa-f]+' | tr 'a-f' 'A-F' | sed 's/0X/0x/' | sort -u
}

add_addrs() {
  local added=0 a
  for a in $1; do
    grep -qi "^$a" "$TOML" && continue
    echo "$a = {}" >> "$TOML"
    echo "   + $a"
    added=$((added+1))
  done
  return $added
}

# Branch targets that codegen itself can't resolve ("target not in any function"). These NEVER
# appear as a runtime FATAL — the guest dies on some *other* address first — so harvesting only
# the runtime crash grinds the same chain forever. Registering them as function entries is what
# actually clears them.
codegen_unresolved() {
  grep -oE '^\s+0x[0-9A-Fa-f]+ from 0x[0-9A-Fa-f]+: b ' "$LOGDIR/codegen.log" 2>/dev/null \
    | grep -oE '0x[0-9A-Fa-f]+' | head -n -0 | awk 'NR%2==1' \
    | tr 'a-f' 'A-F' | sed 's/0X/0x/' | sort -u
}

# `rexglue --force` REWRITES every generated TU on every run, so all of them get a fresh
# mtime and the build recompiles all of them — even though registering ONE function only
# changes ONE file. On a retail-sized title (Ridge Racer: 106 TUs) that is ~4 of the ~6
# minutes per bringup iteration, spent recompiling byte-identical source.
#
# So: keep a shadow copy of the last codegen and, for each file whose CONTENT is unchanged,
# restore its previous mtime. The build then skips it. This is safe precisely because the
# comparison is byte-exact — an unchanged source cannot have a stale object.
GENCACHE="$G/.generated_cache"
preserve_unchanged_mtimes() {
  local f b changed=0 unchanged=0
  if [ ! -d "$GENCACHE" ]; then
    mkdir -p "$GENCACHE" && cp -a "$G/generated/." "$GENCACHE/" 2>/dev/null
    echo "   generated: primed mtime cache (first run rebuilds everything)"
    return
  fi
  for f in "$G"/generated/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    if [ -f "$GENCACHE/$b" ] && cmp -s "$f" "$GENCACHE/$b"; then
      touch -r "$GENCACHE/$b" "$f"          # unchanged -> keep old mtime -> build skips it
      unchanged=$((unchanged+1))
    else
      cp -a "$f" "$GENCACHE/$b"             # changed -> keep new mtime -> build recompiles it
      changed=$((changed+1))
    fi
  done
  echo "   generated: $changed changed, $unchanged unchanged (rebuild skipped for those)"
}

run_codegen() {
  ( cd "$G/config" && LD_LIBRARY_PATH="$SDK_OUT" "$SDK_OUT/rexglue" --force codegen "$(basename "$MANIFEST")" ) \
    >"$LOGDIR/codegen.log" 2>&1
  # rexglue segfaults at process exit (cvar FlagRegistrar dtor) AFTER finishing — cosmetic.
  grep -q "Done in" "$LOGDIR/codegen.log" || return 1
  preserve_unchanged_mtimes
}

codegen_and_build() {
  echo "-- codegen"
  run_codegen || { echo "!! CODEGEN-FAIL"; tail -5 "$LOGDIR/codegen.log"; return 1; }

  # Feed codegen's own unresolved branch targets back in, until it reports none.
  local pass
  for pass in 1 2 3 4; do
    local cg_addrs
    cg_addrs=$(codegen_unresolved)
    [ -z "$cg_addrs" ] && break
    echo "   codegen has unresolved branch targets:"
    add_addrs "$cg_addrs"
    [ $? -eq 0 ] && { echo "   ...all already registered, but codegen still can't resolve them"; break; }
    echo "-- codegen (re-run $pass)"
    run_codegen || { echo "!! CODEGEN-FAIL"; tail -5 "$LOGDIR/codegen.log"; return 1; }
  done

  echo "-- build"
  # NOTE: do NOT blanket-delete the generated *.o here. preserve_unchanged_mtimes() has
  # already made the build recompile exactly the TUs whose source actually changed;
  # deleting the objects would throw that away and force a full rebuild every iteration.
  cmake --build "$BUILD" --config Release --target "$NAME" >"$LOGDIR/build.log" 2>&1 || {
    echo "!! BUILD-FAIL"; grep -iE 'error:' "$LOGDIR/build.log" | head -5; return 1; }
  return 0
}

echo "=== bringup: $NAME (SDK: $SDK_SRC) ==="

# If the toml was edited by hand since the last build, the binary is STALE — testing it
# would report an addr we already added and look like "STUCK (different failure class)".
# Rebuild first so iteration 1 tests what the config actually says.
if [ "$RUN_ONLY" != "1" ] && [ -f "$TOML" ] && [ -f "$BIN" ] && [ "$TOML" -nt "$BIN" ]; then
  echo "-- $TOML is newer than the binary: rebuilding before we test"
  codegen_and_build || exit 1
fi

for i in $(seq 1 "$MAX_ITERS"); do
  echo; echo "--- iter $i: run ${SECS}s"
  log=$(run_once)
  echo "   $(classify "$log")"

  [ "$RUN_ONLY" = "1" ] && break

  addrs=$(all_addrs "$log")
  if [ -z "$addrs" ]; then
    echo "   no unresolved-function FATALs — nothing to add (see $log)"
    break
  fi
  add_addrs "$addrs"
  if [ $? -eq 0 ]; then
    echo "   all unresolved addrs already in $TOML — STUCK (different failure class)"
    break
  fi
  codegen_and_build || break
done

echo; echo "=== final ==="
echo "$(classify "$LOGDIR/run.log")"
echo "toml functions: $(grep -c '^0x' "$TOML")"
