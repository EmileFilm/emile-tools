#!/bin/bash
# Builds sfizz_render (sfizz, BSD-2-Clause) for Apple Silicon into dist/:
# sfizz-render-<VERSION>-macos-arm64.zip with the program and every
# licence. It plays a MIDI file through one SFZ instrument into a 32-bit
# float WAV (render.patch; upstream writes 16-bit).
#
# Needs: Xcode's command line tools and CMake.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION")
SFIZZ=f5c6e29f23b8057867c08e88f5f6ac6738baa30b   # sfztools/sfizz, 2025-03-17
WORK=${WORK:-${TMPDIR:-/tmp}/emile-tools/sfizz}
DIST=${DIST:-$HERE/../dist}

rm -rf "$WORK" && mkdir -p "$WORK" "$DIST"
git init -q "$WORK/src" && cd "$WORK/src"
git remote add origin https://github.com/sfztools/sfizz.git
git fetch -q --depth 1 origin "$SFIZZ" && git checkout -q FETCH_HEAD
git submodule update -q --init --recursive --depth 1
# 32-bit float output in place of 16-bit: a quiet part keeps its detail
# when the mix is brought to loudness afterwards
git apply "$HERE/render.patch"

# Newer clang refuses an old template spelling in external/atomic_queue;
# it is a warning there, not an error
cmake -S . -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_CXX_FLAGS="-Wno-missing-template-arg-list-after-template-kw" \
  -DSFIZZ_RENDER=ON -DSFIZZ_JACK=OFF -DSFIZZ_SHARED=OFF -DPLUGIN_LV2=OFF -DPLUGIN_VST3=OFF \
  -DPLUGIN_AU=OFF -DPLUGIN_PUREDATA=OFF -DSFIZZ_DEMOS=OFF -DSFIZZ_DEVTOOLS=OFF \
  -DSFIZZ_BENCHMARKS=OFF -DSFIZZ_TESTS=OFF
cmake --build "$WORK/build" --target sfizz_render -j "$(sysctl -n hw.ncpu)"

NAME=sfizz-render-$VERSION-macos-arm64
PKG="$WORK/$NAME"
mkdir -p "$PKG/LICENSES"
cp "$WORK/build/library/bin/sfizz_render" "$PKG/sfizz_render"
cp LICENSE "$PKG/LICENSES/sfizz.txt"
cp "$HERE/render.patch" "$PKG/LICENSES/"
# Every bundled library's licence, named by where it sits (tests and the
# libraries' own test tools are not built in)
find external src/external \( -iname 'LICENSE*' -o -iname 'COPYING*' \) \
  -not -path '*/test*' -not -path '*/vendors/*' -not -path '*/xmms/*' -not -path '*/platform/*' |
while read -r f; do cp "$f" "$PKG/LICENSES/$(dirname "$f" | sed 's#^external/##; s#^src/external/##; s#/thirdparty/#-#; s#/#-#g').txt"; done
# ThreadPool.h says only "SPDX-License-Identifier: zlib": its licence is
# kept here, from github.com/progschj/ThreadPool
cp "$HERE/licenses/threadpool.txt" "$PKG/LICENSES/threadpool.txt"
cat > "$PKG/README.txt" <<EOF
sfizz_render $VERSION: sfizz (github.com/sfztools/sfizz at $SFIZZ, BSD-2-Clause),
with LICENSES/render.patch (writes 32-bit float). Built by github.com/EmileFilm/emile-tools sfizz/build.sh.
EOF
# A zip, as Émile unpacks its pinned tools with ditto (engine/lib/install.mjs)
(cd "$WORK" && ditto -c -k --keepParent "$NAME" "$DIST/$NAME.zip")
shasum -a 256 "$DIST/$NAME.zip"
