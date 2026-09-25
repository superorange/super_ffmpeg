import '../engine/media_info.dart';

enum VideoCodec {
  h264(['h264_videotoolbox', 'h264_nvenc', 'h264_qsv', 'h264_amf'], ['libx264', 'libopenh264']),
  hevc(['hevc_videotoolbox', 'hevc_nvenc', 'hevc_qsv', 'hevc_amf'], ['libx265']),
  av1(['av1_nvenc', 'av1_qsv', 'av1_amf'], ['libsvtav1', 'libaom-av1']),
  vp9([], ['libvpx-vp9']),
  prores(['prores_videotoolbox'], ['prores_ks', 'prores']),
  copy([], []);

  const VideoCodec(this.gpuEncoders, this.cpuEncoders);
  final List<String> gpuEncoders;
  final List<String> cpuEncoders;

  bool isAvailable(Set<String> encoders) => this == copy || [...gpuEncoders, ...cpuEncoders].any(encoders.contains);
}

enum MediaContainer {
  mp4('mp4', {VideoCodec.h264, VideoCodec.hevc, VideoCodec.av1, VideoCodec.vp9, VideoCodec.copy}),
  mkv('mkv', {...VideoCodec.values}),
  mov('mov', {VideoCodec.h264, VideoCodec.hevc, VideoCodec.prores, VideoCodec.copy}),
  webm('webm', {VideoCodec.vp9, VideoCodec.av1, VideoCodec.copy});

  const MediaContainer(this.extension, this.codecs);
  final String extension;
  final Set<VideoCodec> codecs;

  bool supports(VideoCodec codec) => codecs.contains(codec);

  /// First container (in declaration order) that can hold [codec].
  static MediaContainer bestFor(VideoCodec codec) => values.firstWhere((c) => c.supports(codec));
}

enum QualityLevel { high, balanced, small }

enum EncodeSpeed { fast, medium, slow }

/// Output resolution expressed as the short side, so portrait video works.
enum Resolution {
  original(null),
  p2160(2160),
  p1440(1440),
  p1080(1080),
  p720(720),
  p480(480);

  const Resolution(this.shortSide);
  final int? shortSide;
}

class EncoderChoice {
  const EncoderChoice(this.encoder, {required this.hardware});
  final String encoder;
  final bool hardware;
}

abstract final class Encoders {
  /// Picks the concrete encoder for [codec] given what ffmpeg supports.
  static EncoderChoice? pick(VideoCodec codec, Set<String> available, {bool preferGpu = true}) {
    if (codec == VideoCodec.copy) return const EncoderChoice('copy', hardware: false);
    final order = preferGpu
        ? [...codec.gpuEncoders, ...codec.cpuEncoders]
        : [...codec.cpuEncoders, ...codec.gpuEncoders];
    for (final e in order) {
      if (available.contains(e)) {
        return EncoderChoice(e, hardware: codec.gpuEncoders.contains(e));
      }
    }
    return null;
  }

  /// Rate-control / quality args for [encoder].
  static List<String> quality(String encoder, QualityLevel q, {EncodeSpeed speed = EncodeSpeed.medium}) {
    int by(int high, int balanced, int small) => switch (q) {
      QualityLevel.high => high,
      QualityLevel.balanced => balanced,
      QualityLevel.small => small,
    };
    String preset(String fast, String medium, String slow) => switch (speed) {
      EncodeSpeed.fast => fast,
      EncodeSpeed.medium => medium,
      EncodeSpeed.slow => slow,
    };

    if (encoder.endsWith('_videotoolbox')) {
      if (encoder.startsWith('prores')) {
        return ['-profile:v', _proresProfile(q)];
      }
      return ['-q:v', '${by(75, 60, 45)}'];
    }
    if (encoder.endsWith('_nvenc')) {
      return ['-preset', preset('p3', 'p5', 'p7'), '-rc', 'vbr', '-cq', '${by(19, 25, 31)}', '-b:v', '0'];
    }
    if (encoder.endsWith('_qsv')) return ['-global_quality', '${by(20, 25, 30)}'];
    if (encoder.endsWith('_amf')) {
      final qp = '${by(20, 25, 30)}';
      return ['-rc', 'cqp', '-qp_i', qp, '-qp_p', qp];
    }
    return switch (encoder) {
      'libx264' => ['-preset', preset('veryfast', 'medium', 'slow'), '-crf', '${by(18, 23, 28)}'],
      'libx265' => ['-preset', preset('veryfast', 'medium', 'slow'), '-crf', '${by(20, 26, 30)}'],
      'libsvtav1' => ['-preset', preset('10', '8', '6'), '-crf', '${by(28, 35, 42)}'],
      'libaom-av1' => ['-cpu-used', preset('6', '4', '3'), '-crf', '${by(28, 35, 42)}', '-b:v', '0'],
      'libvpx-vp9' => [
        '-deadline',
        'good',
        '-cpu-used',
        preset('4', '2', '1'),
        '-row-mt',
        '1',
        '-crf',
        '${by(28, 33, 38)}',
        '-b:v',
        '0',
      ],
      'prores_ks' || 'prores' => ['-profile:v', _proresProfile(q)],
      'libopenh264' => ['-b:v', '${by(8000, 4000, 2000)}k'],
      _ => const [],
    };
  }

  static String _proresProfile(QualityLevel q) => switch (q) {
    QualityLevel.high => 'hq',
    QualityLevel.balanced => 'standard',
    QualityLevel.small => 'lt',
  };

  /// Container/encoder specific extras (compatibility tags, pixel format).
  static List<String> extras(String encoder, MediaContainer container) {
    final isH264 = encoder.startsWith('h264') || encoder == 'libx264' || encoder == 'libopenh264';
    final isHevc = encoder.startsWith('hevc') || encoder == 'libx265';
    return [
      // 8-bit 4:2:0 is the only H.264 flavour every player handles.
      if (isH264) ...['-pix_fmt', 'yuv420p'],
      // Apple players require the hvc1 tag for HEVC in MP4/MOV.
      if (isHevc && container != MediaContainer.mkv && container != MediaContainer.webm) ...['-tag:v', 'hvc1'],
    ];
  }

  static List<String> containerFlags(MediaContainer container) => switch (container) {
    MediaContainer.mp4 || MediaContainer.mov => ['-movflags', '+faststart'],
    _ => const [],
  };

  /// Default audio encoder for a container.
  static String audioEncoderFor(MediaContainer container, Set<String> available) {
    if (container == MediaContainer.webm) {
      return available.contains('libopus') ? 'libopus' : 'libvorbis';
    }
    return 'aac';
  }
}

/// `scale` filter that brings the short side down to [res] (never upscales).
/// Returns null when no scaling is needed.
String? scaleFilter(Resolution res, MediaStream? video) {
  final target = res.shortSide;
  if (target == null) return null;
  if (video == null || video.displayWidth == 0) return 'scale=-2:$target';
  final w = video.displayWidth;
  final h = video.displayHeight;
  if ((w < h ? w : h) <= target) return null;
  return w >= h ? 'scale=-2:$target' : 'scale=$target:-2';
}

/// `atempo` only accepts 0.5–2.0 per instance; chain for larger factors.
String atempoChain(double speed) {
  final parts = <String>[];
  var s = speed;
  while (s > 2.0 + 1e-9) {
    parts.add('atempo=2.0');
    s /= 2.0;
  }
  while (s < 0.5 - 1e-9) {
    parts.add('atempo=0.5');
    s /= 0.5;
  }
  if ((s - 1.0).abs() > 1e-9 || parts.isEmpty) parts.add('atempo=${_num(s)}');
  return parts.join(',');
}

String _num(double v) {
  final s = v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? '${s}0' : s;
}

String fmtNum(double v) => _num(v);
