import 'dart:io';

import 'ffmpeg_locator.dart';

/// What the local ffmpeg build can actually do.
class FfmpegCapabilities {
  const FfmpegCapabilities({
    required this.binaries,
    required this.version,
    required this.encoders,
    required this.hwaccels,
  });

  final FfmpegBinaries binaries;
  final String version;
  final Set<String> encoders;
  final Set<String> hwaccels;

  bool has(String encoder) => encoders.contains(encoder);

  static const _gpuEncoderMarkers = ['videotoolbox', 'nvenc', 'qsv', 'amf', 'vaapi'];

  /// GPU video encoders present in the build (e.g. `h264_videotoolbox`).
  List<String> get gpuEncoders => [
    for (final e in encoders)
      if (_gpuEncoderMarkers.any(e.endsWith)) e,
  ]..sort();

  bool get hasGpu => gpuEncoders.isNotEmpty;

  static Future<FfmpegCapabilities> detect(FfmpegBinaries bin) async {
    final results = await Future.wait([
      Process.run(bin.ffmpeg, ['-hide_banner', '-version']),
      Process.run(bin.ffmpeg, ['-hide_banner', '-encoders']),
      Process.run(bin.ffmpeg, ['-hide_banner', '-hwaccels']),
    ]);
    return FfmpegCapabilities(
      binaries: bin,
      version: parseVersion(results[0].stdout as String),
      encoders: parseEncoders(results[1].stdout as String),
      hwaccels: parseHwaccels(results[2].stdout as String),
    );
  }

  static String parseVersion(String output) {
    final match = RegExp(r'ffmpeg version (\S+)').firstMatch(output);
    return match?.group(1) ?? 'unknown';
  }

  /// Parses `ffmpeg -encoders`: lines like ` V....D libx264   libx264 H.264 …`.
  static Set<String> parseEncoders(String output) {
    final line = RegExp(r'^\s*[VAS][F.][S.][X.][B.][D.]\s+(\S+)', multiLine: true);
    return {
      for (final m in line.allMatches(output))
        if (m.group(1) != '=') m.group(1)!,
    };
  }

  static Set<String> parseHwaccels(String output) {
    return output.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !l.endsWith(':')).toSet();
  }
}
