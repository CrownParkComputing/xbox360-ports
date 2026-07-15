#!/usr/bin/env bash
# Scaffold a new XBLA game port from the working hydrothunder template, then
# extract -> codegen -> configure -> build. Follow with tools/bringup.sh to grind
# out the unresolved-function FATALs.
#
#   tools/newgame.sh rainbowislands ri "/home/jon/RAINBOW ISLANDS.../584109C3/000D0000"
#
# The package_dir is the 000D0000 FOLDER; the extractor is handed the STFS FILE inside it.
set -u

NAME="${1:?usage: newgame.sh <name> <prefix> <package_dir>}"
PREFIX="${2:?missing prefix, e.g. ri}"
PKGDIR="${3:?missing package dir (the .../000D0000 folder)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEMPLATE="games/hydrothunder"
G="games/$NAME"

# Build against the OFFICIAL rexglue (the one HT/OutRun/jetpac use), not the suite's fork.
SDK_SRC="${SDK_SRC:-/home/jon/development/xenon-native/repos/rexglue-sdk}"
SDK_OUT="$SDK_SRC/out/linux-amd64/Release"

ulimit -c 0

if [ -d "$G" ]; then echo "!! $G already exists — remove it first"; exit 1; fi
[ -d "$PKGDIR" ] || { echo "!! package dir not found: $PKGDIR"; exit 1; }

echo "=== 1. scaffold $G from $TEMPLATE ==="
mkdir -p "$G/config" "$G/logs"
cp -r "$TEMPLATE/project" "$G/project"
cp -r "$TEMPLATE/ppc" "$G/ppc"
rm -rf "$G/project/out"                      # never inherit the template's build tree
# Rename in CMakeLists AND the sources — src/main.cpp + src/stubs.cpp #include
# "<name>_init.h", which codegen emits under the NEW game's name.
sed -i "s/hydrothunder/$NAME/g" "$G/project/CMakeLists.txt"
find "$G/project/src" -type f \( -name '*.cpp' -o -name '*.h' \) \
  -exec sed -i "s/hydrothunder/$NAME/g" {} +
# the template's codegen custom-target still points at the old manifest name
sed -i "s#/config/[a-z0-9]*_manifest.toml#/config/${PREFIX}_manifest.toml#" "$G/project/CMakeLists.txt"

cat > "$G/config/${PREFIX}_manifest.toml" <<EOF
[project]
sdk_version = "0.8.0"
name = "$NAME"
[entrypoint]
file_path = "../assets/default.xex"
out_directory_path = "../generated"
includes = [ "${PREFIX}_rexglue.toml" ]
EOF

cat > "$G/config/${PREFIX}_rexglue.toml" <<EOF
[analysis]
max_jump_extension = 65536
data_region_threshold = 16

[functions]
EOF
echo "   wrote config/${PREFIX}_manifest.toml + ${PREFIX}_rexglue.toml"

echo "=== 2. extract STFS package ==="
pkg=$(find "$PKGDIR" -maxdepth 1 -type f | head -1)
[ -n "$pkg" ] || { echo "!! no file inside $PKGDIR"; exit 1; }
echo "   package: $pkg"
python3 tools/extract_game.py "$pkg" --out "$G/extracted" --assets "$G/assets" \
  > "$G/logs/extract.log" 2>&1 || { echo "!! EXTRACT FAILED"; tail -5 "$G/logs/extract.log"; exit 1; }
[ -f "$G/assets/default.xex" ] || { echo "!! no default.xex produced"; exit 1; }
echo "   ok: $(du -sh "$G/extracted" | cut -f1) extracted"

echo "=== 3. codegen (rexglue segfaults at exit AFTER 'Done in' — cosmetic) ==="
( cd "$G/config" && LD_LIBRARY_PATH="$SDK_OUT" "$SDK_OUT/rexglue" --force codegen "${PREFIX}_manifest.toml" ) \
  > "$G/logs/codegen.log" 2>&1
grep -q "Done in" "$G/logs/codegen.log" || { echo "!! CODEGEN FAILED"; tail -6 "$G/logs/codegen.log"; exit 1; }
echo "   ok: $(ls "$G/generated"/*.cpp 2>/dev/null | wc -l) TUs, \
$(grep -c 'Unresolved' "$G/logs/codegen.log" 2>/dev/null) unresolved warnings"

echo "=== 4. configure + build ==="
cmake --preset linux-amd64 -S "$G/project" -DREXGLUE_SDK_SOURCE_DIR="$SDK_SRC" \
  > "$G/logs/configure.log" 2>&1 || { echo "!! CONFIGURE FAILED"; tail -6 "$G/logs/configure.log"; exit 1; }
cmake --build "$G/project/out/build/linux-amd64" --config Release --target "$NAME" \
  > "$G/logs/build.log" 2>&1 || { echo "!! BUILD FAILED"; grep -iE 'error:' "$G/logs/build.log" | head -5; exit 1; }
echo "   ok: $(ls -lh "$G/project/out/build/linux-amd64/Release/$NAME" | awk '{print $5}') binary"

echo
echo "=== done. now grind the unresolved functions: ==="
echo "    tools/bringup.sh $NAME $PREFIX"
