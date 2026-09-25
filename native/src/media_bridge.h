// In-process media inspection for Super Toolbox, called from Dart via FFI.
// Transcoding does NOT go through here — it runs the bundled ffmpeg executable
// (parallel jobs, crash isolation, reliable cancel). This bridge covers the
// high-frequency, latency-sensitive calls: probing and frame decoding.
#ifndef MEDIA_BRIDGE_H
#define MEDIA_BRIDGE_H

#include <stdint.h>

#define MB_EXPORT __attribute__((visibility("default")))

// FFmpeg version string of the linked libraries (static, do not free).
MB_EXPORT const char *mb_version(void);

// Probes a file. Returns malloc'd JSON shaped like a subset of
// `ffprobe -print_format json -show_format -show_streams`, or
// {"error":"..."} on failure. Free with mb_free().
MB_EXPORT char *mb_probe(const char *path);

// Decodes the video frame at time_us (or the cover art for audio files),
// applies the display rotation and scales it to fit max_width x max_height
// (0 = unbounded) keeping aspect ratio. Returns a malloc'd RGBA buffer
// (stride = width * 4) and writes its size, or NULL on failure with a
// message in error_out (if non-NULL, size error_len). Free with mb_free().
MB_EXPORT uint8_t *mb_decode_frame(const char *path, int64_t time_us, int32_t max_width,
                                   int32_t max_height, int32_t *out_width, int32_t *out_height,
                                   char *error_out, int32_t error_len);

MB_EXPORT void mb_free(void *ptr);

#endif
