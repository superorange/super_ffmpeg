import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import 'codecs.dart';

enum CompressMode { quality, targetSize }

/// How hard to squeeze in quality mode.
enum CompressLevel { light, standard, strong }

class CompressOptions {
  const CompressOptions({
    this.mode = CompressMode.quality,
    this.level = CompressLevel.standard,
    this.useHevc = false,
    this.targetMb = 25,
    this.resolution = Resolution.original,
  });

  final CompressMode mode;
  final CompressLevel level;

  /// HEVC gives ~40% smaller files but plays in fewer places.
  final bool useHevc;

  /// Target size in MiB (what file managers and chat apps show as "MB").
  final double targetMb;
  final Resolution resolution;

  CompressOptions copyWith({
    CompressMode? mode,
    CompressLevel? level,
    bool? useHevc,
    double? targetMb,
    Resolution? resolution,
  }) {
    return CompressOptions(
      mode: mode ?? this.mode,
      level: level ?? this.level,
      useHevc: useHevc ?? this.useHevc,
      targetMb: targetMb ?? this.targetMb,
      resolution: resolution ?? this.resolution,
    );
  }
}

/// Bitrate budget for target-size mode.
class SizeBudget {
  const SizeBudget({required this.videoKbps, required this.audioKbps});
  final int videoKbps;
  final int audioKbps;

  static const minVideoKbps = 60;

  /// 4% headroom for container overhead and rate-control variance.
  static SizeBudget compute({
    required double targetMb,
    required Duration duration,
    required bool hasAudio,
  }) {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds <= 0) throw const PlanException('media.errors.unknown_duration');
    final totalKbps = targetMb * 1024 * 1024 * 8 * 0.96 / seconds / 1000;
    final audioKbps = !hasAudio ? 0 : (totalKbps < 600 ? 64 : 128);
    final videoKbps = (totalKbps - audioKbps).floor();
    if (videoKbps < minVideoKbps) {
      throw PlanException('media.errors.target_too_small', {
        'min': (((minVideoKbps + audioKbps) * 1000 * seconds / 8 / 0.96) / (1024 * 1024)).toStringAsFixed(1),
      });
    }
    return SizeBudget(videoKbps: videoKbps, audioKbps: audioKbps);
  }
}

/// Short side to downscale to so the bitrate budget stays watchable
/// (≥ ~0.04 bits per pixel), or null when the source size is fine.
int? autoShortSideForBudget(int videoKbps, MediaStream? video) {
  if (video == null || video.width == 0) return null;
  final fps = (video.frameRate ?? 30).clamp(1, 120);
  final w = video.displayWidth, h = video.displayHeight;
  final short = w < h ? w : h;
  double bpp(int shortSide) {
    final scale = shortSide / short;
    return videoKbps * 1000 / (w * scale * h * scale * fps);
  }

  if (bpp(short) >= 0.04) return null;
  for (final candidate in const [1080, 720, 480, 360]) {
    if (candidate < short && bpp(candidate) >= 0.04) return candidate;
  }
  return short > 360 ? 360 : null;
}

CommandPlan buildCompress({
  required String input,
  required String output,
  required CompressOptions options,
  required Set<String> encoders,
  MediaInfo? info,
  String passLogPrefix = '/tmp/super_toolbox_2pass',
  String nullSink = '/dev/null',
}) {
  final o = options;
  var scale = scaleFilter(o.resolution, info?.video);
  var vf = [
    if (scale != null) ...['-vf', scale],
  ];

  if (o.mode == CompressMode.targetSize) {
    if (!encoders.contains('libx264')) {
      throw const PlanException('media.errors.encoder_missing', {'codec': 'libx264'});
    }
    final budget = SizeBudget.compute(
      targetMb: o.targetMb,
      duration: info?.duration ?? Duration.zero,
      hasAudio: info?.hasAudio ?? true,
    );
    if (o.resolution == Resolution.original) {
      final short = autoShortSideForBudget(budget.videoKbps, info?.video);
      if (short != null) {
        final v = info!.video!;
        scale = v.displayWidth >= v.displayHeight ? 'scale=-2:$short' : 'scale=$short:-2';
        vf = ['-vf', scale];
      }
    }
    final common = [
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-b:v',
      '${budget.videoKbps}k',
      '-pix_fmt',
      'yuv420p',
      ...vf,
      '-passlogfile',
      passLogPrefix,
    ];
    return CommandPlan(
      steps: [
        FfmpegStep(['-y', '-i', input, ...common, '-pass', '1', '-an', '-f', 'null', nullSink], label: 'Pass 1'),
        FfmpegStep([
          '-i',
          input,
          ...common,
          '-pass',
          '2',
          if (budget.audioKbps > 0) ...['-c:a', 'aac', '-b:a', '${budget.audioKbps}k'] else '-an',
          '-movflags',
          '+faststart',
          '-n',
          output,
        ], label: 'Pass 2'),
      ],
      outputs: [output],
      expectedDuration: info?.duration,
      scratchPrefixes: [passLogPrefix],
      maxOutputBytes: (o.targetMb * 1024 * 1024).floor(),
    );
  }

  final hevc = o.useHevc && encoders.contains('libx265');
  if (!hevc && !encoders.contains('libx264')) {
    throw const PlanException('media.errors.encoder_missing', {'codec': 'libx264'});
  }
  final crf = switch ((hevc, o.level)) {
    (false, CompressLevel.light) => 23,
    (false, CompressLevel.standard) => 26,
    (false, CompressLevel.strong) => 30,
    (true, CompressLevel.light) => 25,
    (true, CompressLevel.standard) => 28,
    (true, CompressLevel.strong) => 32,
  };
  return CommandPlan.single(
    [
      '-i',
      input,
      '-c:v',
      hevc ? 'libx265' : 'libx264',
      '-preset',
      'medium',
      '-crf',
      '$crf',
      if (hevc) ...['-tag:v', 'hvc1'] else ...['-pix_fmt', 'yuv420p'],
      ...vf,
      '-c:a',
      'aac',
      '-b:a',
      o.level == CompressLevel.strong ? '96k' : '128k',
      '-movflags',
      '+faststart',
      '-n',
      output,
    ],
    output: output,
    expectedDuration: info?.duration,
  );
}
