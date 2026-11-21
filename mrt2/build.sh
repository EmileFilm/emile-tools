#!/bin/bash
# Builds mrt2 (Magenta RealTime 2 with core.patch and Émile's front end,
# main.cpp) for Apple Silicon into dist/: mrt2-<VERSION>-macos-arm64.zip
# with the program, MLX's mlx.metallib beside it and every licence.
#
# Needs: Xcode with its Metal toolchain (xcodebuild -downloadComponent
# MetalToolchain) and CMake older than 3.28 (Magenta's build asks for it:
# pip install "cmake<3.28").
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION")
MAGENTA=694a545e4ba0b88bf1150137b129582166d3e07f   # magenta/magenta-realtime, 2026-07-30
WORK=${WORK:-${TMPDIR:-/tmp}/emile-tools/mrt2}
DIST=${DIST:-$HERE/../dist}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

case "$(cmake --version | head -1)" in
  *" 3.2"[89]*|*" 3.3"*|*" 4."*) echo "CMake older than 3.28 is needed (pip install 'cmake<3.28')" >&2; exit 1 ;;
esac

rm -rf "$WORK" && mkdir -p "$WORK" "$DIST"
git init -q "$WORK/src" && cd "$WORK/src"
git remote add origin https://github.com/magenta/magenta-realtime.git
git fetch -q --depth 1 origin "$MAGENTA" && git checkout -q FETCH_HEAD
git submodule update -q --init --depth 1
git apply "$HERE/core.patch"
mkdir examples/emile_mrt2 && cp "$HERE/main.cpp" "$HERE/CMakeLists.txt" examples/emile_mrt2/
echo 'add_subdirectory(examples/emile_mrt2)' >> CMakeLists.txt

cmake -S . -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/build" --target mrt2 -j "$(sysctl -n hw.ncpu)"

NAME=mrt2-$VERSION-macos-arm64
PKG="$WORK/$NAME"
mkdir -p "$PKG/LICENSES"
cp "$(find "$WORK/build" -name mrt2 -type f -perm -u+x | head -1)" "$PKG/mrt2"
cp "$(find "$WORK/build" -name mlx.metallib | head -1)" "$PKG/mlx.metallib"
cp LICENSE "$PKG/LICENSES/magenta-realtime.txt"
for d in "$WORK"/build/_deps/*-src; do
  f=$(find "$d" -maxdepth 1 \( -iname 'LICENSE*' -o -iname 'COPYING*' \) | head -1)
  [ -n "$f" ] && cp "$f" "$PKG/LICENSES/$(basename "$d" -src).txt"
done
cp "$HERE/core.patch" "$HERE/main.cpp" "$PKG/LICENSES/"
cat > "$PKG/README.txt" <<EOF
mrt2 $VERSION: Magenta RealTime 2 (github.com/magenta/magenta-realtime at $MAGENTA,
Apache-2.0) with the changes in LICENSES/core.patch and Émile's front end
LICENSES/main.cpp. Built by github.com/EmileFilm/emile-tools mrt2/build.sh.
The model weights are not here (google/magenta-realtime-2, CC-BY-4.0).
EOF
# A zip, as Émile unpacks its pinned tools with ditto (engine/lib/install.mjs)
(cd "$WORK" && ditto -c -k --keepParent "$NAME" "$DIST/$NAME.zip")
shasum -a 256 "$DIST/$NAME.zip"
