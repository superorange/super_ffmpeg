import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import 'codecs.dart';

enum FramesMode { single, interval, contactSheet }

enum ImageFormat {
  jpg('jpg'),
  png('png');

  const ImageFormat(this.extension);
  final String extension;

  List<String> get qualityArgs => this == jpg ? const ['-q:v', '2'] : const [];
}

class FramesOptions {
  const FramesOptions({
    this.mode = FramesMode.single,
    this.at = const Duration(seconds: 1),
    this.everySeconds = 10,
    this.columns = 4,
    this.rows = 4,
    this.format = ImageFormat.jpg,
    this.width,
  });

  final FramesMode mode;
  final Duration at;
  final double everySeconds;
  final int columns;
  final int rows;
  final ImageFormat format;

  /// Frame width (tile width for contact sheets); null = source.
  final int? width;

  FramesOptions copyWith({
    FramesMode? mode,
    Duration? at,
    double? everySeconds,
    int? columns,
    int? rows,
    ImageFormat? format,
    int? Function()? width,
  }) {
    return FramesOptions(
      mode: mode ?? this.mode,
      at: at ?? this.at,
      everySeconds: everySeconds ?? this.everySeconds,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      format: format ?? this.format,
      width: width != null ? width() : this.width,
    );
  }
}

/// [output] is a file for single/contact sheet, a folder for interval mode.
CommandPlan buildFrames({
  required String input,
  required String output,
  required FramesOptions options,
  MediaInfo? info,
}) {
  final o = options;
  if (info != null && !info.hasVideo) throw const PlanException('media.errors.no_video');
  final scale = o.width != null ? 'scale=${o.width}:-2' : null;

  switch (o.mode) {
    case FramesMode.single:
      final at = info != null && info.duration > Duration.zero && o.at >= info.duration ? Duration.zero : o.at;
      return CommandPlan.single([
        '-ss',
        Fmt.seconds(at),
        '-i',
        input,
        '-frames:v',
        '1',
        if (scale != null) ...['-vf', scale],
        ...o.format.qualityArgs,
        '-n',
        output,
      ], output: output);

    case FramesMode.interval:
      if (o.everySeconds <= 0) throw const PlanException('media.errors.invalid_interval');
      final name = p.basenameWithoutExtension(input);
      return CommandPlan(
        steps: [
          FfmpegStep([
            '-i',
            input,
            '-vf',
            ['fps=1/${fmtNum(o.everySeconds)}', ?scale].join(','),
            ...o.format.qualityArgs,
            '-n',
            p.join(output, '${name}_%04d.${o.format.extension}'),
          ]),
        ],
        outputs: [output],
        createDirs: [output],
        expectedDuration: info?.duration,
      );

    case FramesMode.contactSheet:
      final count = o.columns * o.rows;
      final seconds = (info?.duration.inMilliseconds ?? 0) / 1000;
      // Sample `count` frames evenly across the whole video.
      final rate = seconds > 0 ? '$count/${fmtNum(seconds)}' : '1/10';
      return CommandPlan.single(
        [
          '-i',
          input,
          '-vf',
          [
            'fps=$rate',
            'scale=${o.width ?? 320}:-2',
            'tile=${o.columns}x${o.rows}:padding=6:margin=6:color=0x111111',
          ].join(','),
          '-frames:v',
          '1',
          ...o.format.qualityArgs,
          '-n',
          output,
        ],
        output: output,
        expectedDuration: info?.duration,
      );
  }
}
