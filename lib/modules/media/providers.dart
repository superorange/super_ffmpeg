import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import 'engine/capabilities.dart';
import 'engine/ffmpeg_locator.dart';
import 'engine/media_info.dart';
import 'engine/native_media.dart';
import 'engine/probe.dart';

class EngineMissingException implements Exception {
  const EngineMissingException();
}

/// Located ffmpeg/ffprobe binaries (null when not installed).
final ffmpegBinariesProvider = Provider<FfmpegBinaries?>((ref) {
  final dir = ref.watch(settingsProvider.select((s) => s.ffmpegDir));
  return FfmpegLocator.locate(customDir: dir);
});

final ffmpegCapabilitiesProvider = FutureProvider<FfmpegCapabilities>((ref) async {
  final bin = ref.watch(ffmpegBinariesProvider);
  if (bin == null) throw const EngineMissingException();
  return FfmpegCapabilities.detect(bin);
});

/// True when the in-process FFmpeg bridge (FFI) is loadable.
final nativeMediaAvailableProvider = Provider<bool>((ref) => NativeMedia.isAvailable);

final probeProvider = FutureProvider.family<MediaInfo, String>((ref, path) async {
  if (ref.watch(nativeMediaAvailableProvider)) return NativeMedia.probe(path);
  final bin = ref.watch(ffmpegBinariesProvider);
  if (bin == null) throw const EngineMissingException();
  return MediaProbe.probe(bin, path);
});

/// Representative frame for file cards (kept for the session).
final thumbnailProvider = FutureProvider.family<ui.Image?, String>((ref, path) async {
  final info = await ref.watch(probeProvider(path).future);
  final image = await _frame(ref, info, MediaProbe.thumbnailTime(info), 480);
  if (image != null) ref.onDispose(image.dispose);
  return image;
});

/// Frame at an arbitrary time (trim / GIF / frames tools). Auto-disposed so
/// scrubbing doesn't accumulate images.
final framePreviewProvider = FutureProvider.autoDispose.family<ui.Image?, ({String path, int ms})>((ref, req) async {
  final info = await ref.watch(probeProvider(req.path).future);
  final image = await _frame(ref, info, Duration(milliseconds: req.ms), 960);
  if (image != null) ref.onDispose(image.dispose);
  return image;
});

Future<ui.Image?> _frame(Ref ref, MediaInfo info, Duration at, int size) async {
  if (!info.hasVideo && !info.hasCoverArt) return null;
  try {
    if (ref.read(nativeMediaAvailableProvider) && !info.isTiledImage) {
      try {
        final frame = await NativeMedia.decodeFrame(info.path, at: at, maxWidth: size, maxHeight: size);
        return await frame.toImage();
      } on ProbeException {
        if (at == Duration.zero) rethrow;
        // Seeking past the last frame (stills, short clips): use the first.
        final frame = await NativeMedia.decodeFrame(info.path, maxWidth: size, maxHeight: size);
        return await frame.toImage();
      }
    }
    final bin = ref.read(ffmpegBinariesProvider);
    if (bin == null) return null;
    final file = await MediaProbe.thumbnail(bin, info, at: at, width: size);
    if (file == null) return null;
    final codec = await ui.instantiateImageCodec(await File(file).readAsBytes());
    return (await codec.getNextFrame()).image;
  } on ProbeException {
    return null;
  }
}

/// Evenly spaced small frames for the studio timeline. Decoded one after
/// another (each ~5–15 ms in-process); empty when the FFI bridge is missing.
final filmstripProvider = FutureProvider.autoDispose.family<List<ui.Image>, ({String path, int count})>((
  ref,
  req,
) async {
  final info = await ref.watch(probeProvider(req.path).future);
  if (!info.hasVideo || info.duration <= Duration.zero || !ref.read(nativeMediaAvailableProvider)) {
    return const [];
  }
  final frames = <ui.Image>[];
  ref.onDispose(() {
    for (final f in frames) {
      f.dispose();
    }
  });
  final step = info.duration.inMicroseconds / req.count;
  for (var i = 0; i < req.count; i++) {
    try {
      final at = Duration(microseconds: (step * (i + 0.5)).round());
      final frame = await NativeMedia.decodeFrame(info.path, at: at, maxWidth: 240, maxHeight: 136);
      frames.add(await frame.toImage());
    } on ProbeException {
      break;
    }
  }
  return frames;
});
