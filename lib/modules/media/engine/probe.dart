import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'ffmpeg_locator.dart';
import 'media_info.dart';

class ProbeException implements Exception {
  const ProbeException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class MediaProbe {
  static Future<MediaInfo> probe(FfmpegBinaries bin, String path) async {
    final result = await Process.run(
      bin.ffprobe,
      ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path],
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
      stderrEncoding: const Utf8Codec(allowMalformed: true),
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw ProbeException(err.isEmpty ? 'ffprobe failed (${result.exitCode})' : err.split('\n').last);
    }
    return MediaInfo.fromProbeJson(path, result.stdout as String);
  }

  /// A representative moment: 10% in, at most 3 s (skips black intros).
  /// 10% in (max 3 s) to skip black intros; stills (≤ 1 s, single frame)
  /// use their only frame.
  static Duration thumbnailTime(MediaInfo info) => info.hasVideo && info.duration > const Duration(seconds: 1)
      ? Duration(milliseconds: (info.duration.inMilliseconds * 0.1).clamp(0, 3000).round())
      : Duration.zero;

  /// Extracts a small JPEG preview frame into the temp cache. Returns null for
  /// media without pictures.
  static Future<String?> thumbnail(
    FfmpegBinaries bin,
    MediaInfo info, {
    Duration? at,
    int width = 360,
  }) async {
    if (!info.hasVideo && !info.hasCoverArt) return null;
    final dir = Directory(p.join(Directory.systemTemp.path, 'super_toolbox', 'thumbs'))..createSync(recursive: true);
    final stat = File(info.path).statSync();
    final time = at ?? thumbnailTime(info);
    final key = crypto.md5
        .convert(utf8.encode('${info.path}|${stat.modified.millisecondsSinceEpoch}|${time.inMilliseconds}|$width'))
        .toString();
    final out = p.join(dir.path, '$key.jpg');
    if (File(out).existsSync()) return out;

    final result = await Process.run(bin.ffmpeg, [
      '-hide_banner',
      '-nostdin',
      '-v',
      'error',
      if (info.hasVideo) ...['-ss', '${time.inMilliseconds / 1000}'],
      '-i',
      info.path,
      // Tiled HEIF: scale the composed grid (stream group), not one tile.
      if (info.isTiledImage) ...[
        '-filter_complex',
        '[0:g:0]scale=$width:-2[t]',
        '-map',
        '[t]',
      ] else ...[
        '-map',
        info.hasVideo ? '0:${info.video!.index}' : '0:v:0',
        '-vf',
        'scale=$width:-2',
      ],
      '-frames:v',
      '1',
      '-q:v',
      '4',
      '-y',
      out,
    ]);
    return result.exitCode == 0 && File(out).existsSync() ? out : null;
  }
}
