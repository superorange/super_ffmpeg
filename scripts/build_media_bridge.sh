#!/usr/bin/env bash
# Compiles native/src/media_bridge.c (in-process probe / frame decode via FFI)
# against the bundled FFmpeg. Output: vendor/ffmpeg/darwin-<arch>/lib/libmedia_bridge.dylib
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
PREFIX="$ROOT/vendor/ffmpeg/darwin-$ARCH"
[[ -f "$PREFIX/include/libavformat/avformat.h" ]] || { echo "Run scripts/build_ffmpeg.sh first" >&2; exit 1; }

clang -arch "$ARCH" -mmacosx-version-min=12.0 -O2 -Wall -Wextra -Werror -std=c11 -fPIC -shared \
  -I"$PREFIX/include" "$ROOT/native/src/media_bridge.c" \
  -L"$PREFIX/lib" -lavformat -lavcodec -lavutil -lswscale \
  -install_name @rpath/libmedia_bridge.dylib -Wl,-rpath,@loader_path \
  -o "$PREFIX/lib/libmedia_bridge.dylib"
echo "built $PREFIX/lib/libmedia_bridge.dylib"
