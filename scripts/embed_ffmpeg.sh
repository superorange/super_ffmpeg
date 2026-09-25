#!/usr/bin/env bash
# Xcode "Embed FFmpeg" build phase: copies the bundled FFmpeg into the .app
#   Contents/MacOS/{ffmpeg,ffprobe}        — transcoding (spawned as processes)
#   Contents/Frameworks/*.dylib            — shared libav* + libmedia_bridge (FFI)
# and signs them before Xcode signs the app. If both arm64 and x86_64 builds
# exist they are merged into universal binaries.
set -euo pipefail

ROOT="${SRCROOT:?run from Xcode}/.."
VENDOR="$ROOT/vendor/ffmpeg"
APP="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
MACOS_DIR="$APP/Contents/MacOS"
FW_DIR="$APP/Contents/Frameworks"

builds=()
for arch in arm64 x86_64; do
  [[ -x "$VENDOR/darwin-$arch/bin/ffmpeg" && -f "$VENDOR/darwin-$arch/lib/libmedia_bridge.dylib" ]] &&
    builds+=("$VENDOR/darwin-$arch")
done
if [[ ${#builds[@]} -eq 0 ]]; then
  echo "warning: bundled FFmpeg not built — run scripts/build_ffmpeg.sh. The app will fall back to a system ffmpeg."
  exit 0
fi

mkdir -p "$MACOS_DIR" "$FW_DIR"

# Skip when this exact FFmpeg build is already embedded — rewriting signed
# files would invalidate the app's seal on incremental builds.
# (Kept outside the bundle: non-code files in Frameworks break the app seal.)
rm -f "$FW_DIR/.ffmpeg-embed.stamp"
stamp_file="${TARGET_TEMP_DIR:-$DERIVED_FILE_DIR}/ffmpeg-embed-$(basename "$APP").stamp"
stamp="$(for b in "${builds[@]}"; do find "$b/bin" "$b/lib" -type f \( -name 'ff*' -o -name '*.dylib' \) -exec shasum {} +; done | shasum | cut -d' ' -f1)"
if [[ -f "$stamp_file" && "$(cat "$stamp_file")" == "$stamp" && -x "$MACOS_DIR/ffmpeg" ]]; then
  echo "Bundled FFmpeg up to date"
  exit 0
fi

# place <relative path in build> <destination>
place() {
  local rel="$1" dest="$2" inputs=()
  for b in "${builds[@]}"; do inputs+=("$b/$rel"); done
  rm -f "$dest"
  if [[ ${#inputs[@]} -gt 1 ]]; then
    lipo -create "${inputs[@]}" -output "$dest"
  else
    cp -L "${inputs[0]}" "$dest"
  fi
  chmod u+w "$dest"
}

primary="${builds[0]}"
for exe in ffmpeg ffprobe; do
  place "bin/$exe" "$MACOS_DIR/$exe"
done

# Each dylib is copied under its install name (e.g. libavcodec.62.dylib),
# which is what @rpath lookups ask for.
for lib in "$primary"/lib/*.dylib; do
  [[ -L "$lib" ]] && continue
  id="$(otool -D "$lib" | tail -1)"
  place "lib/$(basename "$lib")" "$FW_DIR/$(basename "$id")"
done

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[[ -z "$identity" || "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]] && identity="-"
sign_flags=(--force --sign "$identity" --timestamp=none)
[[ "${ENABLE_HARDENED_RUNTIME:-NO}" == "YES" ]] && sign_flags+=(--options runtime)

for f in "$FW_DIR"/libav*.dylib "$FW_DIR"/libsw*.dylib "$FW_DIR"/libpostproc*.dylib \
  "$FW_DIR/libmedia_bridge.dylib" "$MACOS_DIR/ffmpeg" "$MACOS_DIR/ffprobe"; do
  [[ -f "$f" ]] && codesign "${sign_flags[@]}" "$f"
done

echo "$stamp" >"$stamp_file"

# Xcode only re-signs the app when it sees its own inputs change; re-seal it
# here so an incremental build that only swapped FFmpeg stays valid.
if codesign -d "$APP" >/dev/null 2>&1; then
  codesign --force --sign "$identity" --timestamp=none \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$APP"
fi

echo "Embedded FFmpeg ($(basename "${builds[*]}" | tr '\n' ' ')) into $WRAPPER_NAME"
