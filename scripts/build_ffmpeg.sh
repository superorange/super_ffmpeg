#!/usr/bin/env bash
# Builds the bundled FFmpeg (GPL, shared libs + ffmpeg/ffprobe) from pinned,
# checksum-verified upstream sources. Output: vendor/ffmpeg/darwin-<arch>/
#
#   scripts/build_ffmpeg.sh            # host arch
#   ARCH=x86_64 scripts/build_ffmpeg.sh
#
# Needs: Xcode CLT, nasm, cmake, meson, ninja, pkg-config (brew install nasm cmake meson ninja pkg-config).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS="12.0" # matches MACOSX_DEPLOYMENT_TARGET of the Runner target
JOBS="$(sysctl -n hw.ncpu)"
# GNU config.sub spells arm64 as aarch64.
[[ "$ARCH" == arm64 ]] && AUTOTOOLS_HOST=aarch64-apple-darwin || AUTOTOOLS_HOST="$ARCH-apple-darwin"

CACHE="$ROOT/vendor/.cache"
SRC="$ROOT/vendor/.src/$ARCH"
PREFIX="$ROOT/vendor/ffmpeg/darwin-$ARCH"

# name|version|url|sha256  (x264 has no release tarballs: pinned git commit)
FFMPEG="ffmpeg|9.0.2|https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz|8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
X264_GIT="https://code.videolan.org/videolan/x264.git"
X264_COMMIT="b35605ace3ddf7c1a5d67a2eb553f034aef41d55"
X265="x265|4.3|https://github.com/Multicorewareinc/x265/releases/download/4.3/x265_4.3.tar.gz|83c53e4c8bbb8f1e33ed59e10a7d621d1d7801ca853910c3eb41f038b8ffb121"
SVTAV1="svt-av1|4.2.0|https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2|512f2ea5649e3e76c2dddcc25c2556fb67a9582baaab207c9c96161c94659dad"
VPX="libvpx|1.17.0|https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz|1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a"
OPUS="opus|1.6.1|https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz|6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
LAME="lame|4.0|https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz|3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb"
DAV1D="dav1d|1.5.4|https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2|2abfb0c89212e6e4733a54e0ae509ec00a5b845a6360946f918806e14aedb011"

log() { printf '\n\033[1;35m[ffmpeg-build]\033[0m %s\n' "$*" >&2; }

for tool in nasm cmake meson ninja pkg-config git curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 1; }
done

export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
export CC=clang CXX=clang++
export CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -O3 -fPIC"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS"
# Only see our own deps — never pick up Homebrew's libraries by accident.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH

CMAKE_COMMON=(
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS"
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

mkdir -p "$CACHE" "$SRC" "$PREFIX"

# fetch <spec> → prints extracted source dir
fetch() {
  IFS='|' read -r name version url sha <<<"$1"
  local file="$CACHE/$(basename "$url")"
  if [[ ! -f "$file" ]]; then
    log "download $name $version"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  local actual; actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  if [[ "$actual" != "$sha" ]]; then
    echo "checksum mismatch for $file: $actual != $sha" >&2; rm -f "$file"; exit 1
  fi
  local dir="$SRC/$name-$version"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    tar -xf "$file" -C "$dir" --strip-components=1
  fi
  echo "$dir"
}

done_marker() { [[ -f "$PREFIX/.built-$1" ]]; }
mark_done() { touch "$PREFIX/.built-$1"; }

build_x264() {
  done_marker x264 && return
  log "x264 @ ${X264_COMMIT:0:10}"
  local dir="$SRC/x264"
  if [[ ! -d "$dir" ]]; then
    git clone --quiet "$X264_GIT" "$dir"
  fi
  git -C "$dir" fetch --quiet origin "$X264_COMMIT" 2>/dev/null || true
  git -C "$dir" checkout --quiet "$X264_COMMIT"
  (cd "$dir" && ./configure --prefix="$PREFIX" --enable-static --enable-pic --disable-cli \
      --host="$ARCH-apple-darwin" --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS" \
    && make -j"$JOBS" && make install)
  mark_done x264
}

# 8/10/12-bit in one static lib (same as Homebrew) so HDR sources keep bit depth.
build_x265() {
  done_marker x265 && return
  local dir; dir="$(fetch "$X265")"
  log "x265 (8/10/12-bit multilib)"
  local b="$dir/_build"; rm -rf "$b"; mkdir -p "$b/8bit" "$b/10bit" "$b/12bit"
  local high=(-DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF)
  (cd "$b/10bit" && cmake "$dir/source" -G Ninja "${CMAKE_COMMON[@]}" "${high[@]}" -DENABLE_HDR10_PLUS=ON && ninja)
  (cd "$b/12bit" && cmake "$dir/source" -G Ninja "${CMAKE_COMMON[@]}" "${high[@]}" -DMAIN12=ON && ninja)
  cp "$b/10bit/libx265.a" "$b/8bit/libx265_main10.a"
  cp "$b/12bit/libx265.a" "$b/8bit/libx265_main12.a"
  (cd "$b/8bit" && cmake "$dir/source" -G Ninja "${CMAKE_COMMON[@]}" \
      -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
      -DEXTRA_LINK_FLAGS=-L. "-DEXTRA_LIB=x265_main10.a;x265_main12.a" \
    && ninja && mv libx265.a libx265_main.a \
    && libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null \
    && ninja install && cp libx265.a "$PREFIX/lib/libx265.a")
  mark_done x265
}

build_svtav1() {
  done_marker svtav1 && return
  local dir; dir="$(fetch "$SVTAV1")"
  log "SVT-AV1"
  rm -rf "$dir/_build"
  cmake -S "$dir" -B "$dir/_build" -G Ninja "${CMAKE_COMMON[@]}" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
  ninja -C "$dir/_build" install
  mark_done svtav1
}

build_vpx() {
  done_marker vpx && return
  local dir; dir="$(fetch "$VPX")"
  log "libvpx"
  local target; [[ "$ARCH" == arm64 ]] && target=arm64-darwin21-gcc || target=x86_64-darwin21-gcc
  (cd "$dir" && ./configure --prefix="$PREFIX" --target="$target" \
      --disable-examples --disable-tools --disable-docs --disable-unit-tests \
      --enable-pic --enable-vp9-highbitdepth --disable-shared --enable-static \
      --extra-cflags="-mmacosx-version-min=$MIN_MACOS" \
    && make -j"$JOBS" && make install)
  mark_done vpx
}

build_autotools() { # <marker> <spec> [extra configure args...]
  local marker="$1" spec="$2"; shift 2
  done_marker "$marker" && return
  local dir; dir="$(fetch "$spec")"
  log "$marker"
  (cd "$dir" && ./configure --prefix="$PREFIX" --host="$AUTOTOOLS_HOST" \
      --disable-shared --enable-static --with-pic "$@" \
    && make -j"$JOBS" && make install)
  mark_done "$marker"
}

build_dav1d() {
  done_marker dav1d && return
  local dir; dir="$(fetch "$DAV1D")"
  log "dav1d"
  rm -rf "$dir/_build"
  meson setup "$dir/_build" "$dir" --prefix="$PREFIX" --libdir=lib --buildtype=release \
    --default-library=static -Denable_tools=false -Denable_tests=false
  ninja -C "$dir/_build" install
  mark_done dav1d
}

build_ffmpeg() {
  done_marker ffmpeg && return
  local dir; dir="$(fetch "$FFMPEG")"
  log "FFmpeg 9.0.2"
  (cd "$dir" && make distclean >/dev/null 2>&1 || true)
  (cd "$dir" && ./configure \
      --prefix="$PREFIX" --install-name-dir='@rpath' \
      --arch="$ARCH" --cc=clang --cxx=clang++ \
      --enable-gpl --enable-shared --disable-static \
      --disable-doc --disable-debug --disable-ffplay \
      --disable-autodetect \
      --enable-videotoolbox --enable-audiotoolbox \
      --enable-zlib --enable-bzlib --enable-iconv --enable-pthreads \
      --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libvpx \
      --enable-libopus --enable-libmp3lame --enable-libdav1d \
      --pkg-config-flags=--static \
      --extra-cflags="-I$PREFIX/include -mmacosx-version-min=$MIN_MACOS" \
      --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=$MIN_MACOS" \
      --extra-libs="-lc++ -liconv" \
      --extra-ldexeflags="-Wl,-rpath,@executable_path/../Frameworks -Wl,-rpath,@executable_path/../lib -Wl,-headerpad_max_install_names" \
      --extra-ldsoflags="-Wl,-rpath,@loader_path -Wl,-headerpad_max_install_names" \
    && make -j"$JOBS" && make install)

  # Search paths are baked in at link time (see --extra-ldexeflags): ../Frameworks
  # inside the .app, ../lib in the dev layout.
  otool -l "$PREFIX/bin/ffmpeg" | grep -q '@executable_path/../Frameworks' || {
    echo "ERROR: ffmpeg is missing its Frameworks rpath" >&2; exit 1; }
  mark_done ffmpeg
}

log "arch=$ARCH  min macOS=$MIN_MACOS  prefix=$PREFIX"
build_x264
build_x265
build_svtav1
build_vpx
build_autotools opus "$OPUS" --disable-doc --disable-extra-programs
build_autotools lame "$LAME" --disable-frontend --disable-decoder
build_dav1d
build_ffmpeg
"$ROOT/scripts/build_media_bridge.sh"

log "done"
"$PREFIX/bin/ffmpeg" -hide_banner -version | head -1
foreign="$(otool -L "$PREFIX/bin/ffmpeg" "$PREFIX"/lib/*.dylib | grep -E '^\s' | grep -v -E '@rpath|/usr/lib/|/System/' || true)"
if [[ -n "$foreign" ]]; then
  echo "ERROR: bundled binaries link to non-bundled libraries:" >&2; echo "$foreign" >&2; exit 1
fi
