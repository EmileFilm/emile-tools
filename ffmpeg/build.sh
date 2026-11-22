#!/bin/bash
# Builds ffmpeg and ffprobe without any GPL part (LGPL-2.1-or-later) into
# dist/: ffmpeg-<VERSION>-macos-<arm64|x64>.zip with both programs and every
# licence. H.264, HEVC and AAC are encoded by the system (VideoToolbox,
# AudioToolbox); linked in, statically: dav1d (reads AV1), libvpx (writes
# VP9), opus, freetype and harfbuzz (the words on a contact sheet).
# Nothing of the machine's own libraries is picked up (--disable-autodetect).
#
#   build.sh [arm64|x64]        (default: arm64; x64 is cross-built)
#
# Needs: Xcode's command line tools, and cmake, meson, ninja and pkg-config
# (pip install cmake meson ninja pkgconf); x64 also nasm, which is built here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(cat "$HERE/VERSION")
ARCH=${1:-arm64}
case $ARCH in arm64) CPU=arm64; FF=aarch64; VPX=arm64-darwin20-gcc;; x64) CPU=x86_64; FF=x86_64; VPX=x86_64-darwin20-gcc;; *) echo "arm64 or x64"; exit 1;; esac
# A fixed place, not the builder's own folders: its path is written into the programs
WORK=/tmp/emile-tools/ffmpeg-$ARCH
DIST=${DIST:-$HERE/../dist}
MIN=13.0
JOBS=$(sysctl -n hw.ncpu)

FFMPEG=9.0.2
FFMPEG_SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
DAV1D=1.5.5
LIBVPX=v1.17.0
OPUS=v1.6.1
FREETYPE=VER-2-15-0
HARFBUZZ=15.2.0
NASM=3.02

rm -rf "$WORK" && mkdir -p "$WORK/out" "$DIST"
OUT=$WORK/out
export PKG_CONFIG_LIBDIR=$OUT/lib/pkgconfig PKG_CONFIG_PATH=
export MACOSX_DEPLOYMENT_TARGET=$MIN
export CFLAGS="-arch $CPU -mmacosx-version-min=$MIN -O2" CXXFLAGS="-arch $CPU -mmacosx-version-min=$MIN -O2" LDFLAGS="-arch $CPU -mmacosx-version-min=$MIN"
get() { git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$WORK/$3"; }

if [ "$ARCH" = x64 ]; then
  curl -fsSL "https://www.nasm.us/pub/nasm/releasebuilds/$NASM/nasm-$NASM.tar.xz" | tar -xJ -C "$WORK"
  (cd "$WORK/nasm-$NASM" && CFLAGS=-O2 LDFLAGS= ./configure --prefix="$WORK/nasm" >/dev/null && make -j"$JOBS" >/dev/null && mkdir -p "$WORK/nasm/bin" && cp nasm "$WORK/nasm/bin/")
  export PATH=$WORK/nasm/bin:$PATH
fi

# meson's own cross file, so the x64 build never looks at this Mac
cat > "$WORK/cross.txt" <<C
[binaries]
c = ['clang']
cpp = ['clang++']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'
nasm = 'nasm'
[host_machine]
system = 'darwin'
cpu_family = '$FF'
cpu = '$FF'
endian = 'little'
[built-in options]
c_args = ['-arch', '$CPU', '-mmacosx-version-min=$MIN']
cpp_args = ['-arch', '$CPU', '-mmacosx-version-min=$MIN']
c_link_args = ['-arch', '$CPU', '-mmacosx-version-min=$MIN']
cpp_link_args = ['-arch', '$CPU', '-mmacosx-version-min=$MIN']
C
mes() { (cd "$WORK/$1" && shift && env -u CFLAGS -u CXXFLAGS -u LDFLAGS meson setup build --cross-file "$WORK/cross.txt" --prefix="$OUT" --libdir=lib --buildtype=release --default-library=static "$@" >/dev/null && ninja -C build install >/dev/null); }

get https://code.videolan.org/videolan/dav1d.git "$DAV1D" dav1d
mes dav1d -Denable_tools=false -Denable_tests=false
get https://github.com/freetype/freetype "$FREETYPE" freetype
mes freetype -Dzlib=disabled -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled -Dbrotli=disabled
get https://github.com/harfbuzz/harfbuzz "$HARFBUZZ" harfbuzz
mes harfbuzz -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dcoretext=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled
get https://github.com/xiph/opus "$OPUS" opus
(cd "$WORK/opus" && cmake -S . -B b -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_OSX_ARCHITECTURES=$CPU -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN -DOPUS_PRESUME_NEON=$([ $ARCH = arm64 ] && echo ON || echo OFF) -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF >/dev/null && cmake --build b -j"$JOBS" --target install >/dev/null)
get https://chromium.googlesource.com/webm/libvpx "$LIBVPX" libvpx
(cd "$WORK/libvpx" && ./configure --target=$VPX --prefix="$OUT" --enable-vp9-highbitdepth --disable-shared --enable-static --disable-examples --disable-tools --disable-docs --disable-unit-tests >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz" -o "$WORK/ffmpeg.tar.xz"
echo "$FFMPEG_SHA256  $WORK/ffmpeg.tar.xz" | shasum -a 256 -c -
tar -xJf "$WORK/ffmpeg.tar.xz" -C "$WORK"
cd "$WORK/ffmpeg-$FFMPEG"
CFG=(--prefix="$OUT" --cc="clang -arch $CPU" --arch=$FF --target-os=darwin --extra-version=emile
  --disable-autodetect --disable-shared --enable-static --disable-doc --disable-debug --disable-ffplay --disable-network
  --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv
  --enable-libdav1d --enable-libvpx --enable-libopus --enable-libfreetype --enable-libharfbuzz
  --pkg-config=pkg-config --pkg-config-flags=--static --extra-cflags="-I$OUT/include" --extra-ldflags="-L$OUT/lib" --extra-libs='-lc++ -liconv')
[ "$ARCH" = x64 ] && CFG+=(--enable-cross-compile)
./configure "${CFG[@]}" > "$WORK/configure.log" 2>&1 || { tail -40 "$WORK/configure.log" ffbuild/config.log; exit 1; }
grep -q '^#define CONFIG_GPL 0' config.h && grep -q '^#define CONFIG_NONFREE 0' config.h
make -j"$JOBS" > "$WORK/make.log" 2>&1 || { tail -40 "$WORK/make.log"; exit 1; }

NAME=ffmpeg-$VERSION-macos-$ARCH
PKG=$WORK/$NAME
mkdir -p "$PKG/LICENSES"
strip -x ffmpeg ffprobe && cp ffmpeg ffprobe "$PKG/"
codesign -f -s - "$PKG/ffmpeg" "$PKG/ffprobe"
# Only the system's own libraries may be linked dynamically
if otool -L "$PKG/ffmpeg" "$PKG/ffprobe" | grep -E '^\s' | grep -vE '^\s+(/usr/lib/|/System/Library/)'; then echo "links something that is not the system's"; exit 1; fi
cp COPYING.LGPLv2.1 "$PKG/LICENSES/ffmpeg.txt"; cp LICENSE.md "$PKG/LICENSES/ffmpeg-LICENSE.md"
cp "$WORK/dav1d/COPYING" "$PKG/LICENSES/dav1d.txt"; cp "$WORK/libvpx/LICENSE" "$PKG/LICENSES/libvpx.txt"; cp "$WORK/libvpx/PATENTS" "$PKG/LICENSES/libvpx-PATENTS.txt"
cp "$WORK/opus/COPYING" "$PKG/LICENSES/opus.txt"; cp "$WORK/freetype/docs/FTL.TXT" "$PKG/LICENSES/freetype.txt"; cp "$WORK/harfbuzz/COPYING" "$PKG/LICENSES/harfbuzz.txt"
cat > "$PKG/README.txt" <<R
ffmpeg and ffprobe $FFMPEG, LGPL-2.1-or-later, for macOS $MIN or later ($ARCH).
Source: https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz, unchanged. Linked in: dav1d $DAV1D,
libvpx $LIBVPX, opus $OPUS, freetype $FREETYPE, harfbuzz $HARFBUZZ. Built by
github.com/EmileFilm/emile-tools ffmpeg/build.sh, which rebuilds it with other versions of them.
Configured with: ${CFG[*]}
R
# Nothing of the builder's machine in what is released
if strings -a "$PKG/ffmpeg" "$PKG/ffprobe" | grep -qE '/Users/|/private/|/var/folders/' || grep -qE '/Users/|/private/|/var/folders/' "$PKG/README.txt"; then echo "a path of this machine is in the build"; exit 1; fi
(cd "$WORK" && ditto -c -k --keepParent "$NAME" "$DIST/$NAME.zip")
shasum -a 256 "$DIST/$NAME.zip"; stat -f %z "$DIST/$NAME.zip"
