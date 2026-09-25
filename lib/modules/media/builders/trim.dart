import '../../../core/utils/format.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';

class TrimOptions {
  const TrimOptions({required this.start, required this.end, this.precise = false});

  final Duration start;
  final Duration end;

  /// Re-encode for frame accuracy; otherwise cut on keyframes losslessly.
  final bool precise;

  Duration get length => end - start;
}

/// Output extension: lossless cuts keep the source container; precise cuts of
/// video produce MP4.
String trimExtension(String inputExt, {required bool precise, required bool hasVideo}) {
  final ext = inputExt.replaceFirst('.', '').toLowerCase();
  if (!precise || !hasVideo) return ext.isEmpty ? 'mp4' : ext;
  return 'mp4';
}

CommandPlan buildTrim({
  required String input,
  required String output,
  required TrimOptions options,
  MediaInfo? info,
}) {
  final o = options;
  if (o.start.isNegative || o.length <= Duration.zero) {
    throw const PlanException('media.errors.invalid_range');
  }
  if (info != null && info.duration > Duration.zero && o.start >= info.duration) {
    throw const PlanException('media.errors.invalid_range');
  }
  final hasVideo = info?.hasVideo ?? true;
  final args = <String>[
    '-ss',
    Fmt.seconds(o.start),
    '-i',
    input,
    '-t',
    Fmt.seconds(o.length),
  ];
  if (!o.precise) {
    args.addAll(['-c', 'copy', '-avoid_negative_ts', 'make_zero']);
  } else if (hasVideo) {
    args.addAll([
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '18',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
    ]);
  }
  args.addAll(['-n', output]);
  return CommandPlan.single(args, output: output, expectedDuration: o.length);
}
