import '../../../core/utils/format.dart';
import '../engine/command_plan.dart';
import '../engine/media_info.dart';

enum GifDither {
  bayer('bayer:bayer_scale=4'),
  floyd('floyd_steinberg'),
  sierra('sierra2_4a'),
  none('none');

  const GifDither(this.value);
  final String value;
}

class GifOptions {
  const GifOptions({
    this.start = Duration.zero,
    this.duration = const Duration(seconds: 5),
    this.fps = 15,
    this.width = 480,
    this.dither = GifDither.sierra,
    this.loop = true,
  });

  final Duration start;

  /// null = until the end.
  final Duration? duration;
  final int fps;

  /// null = source width.
  final int? width;
  final GifDither dither;
  final bool loop;

  GifOptions copyWith({
    Duration? start,
    Duration? Function()? duration,
    int? fps,
    int? Function()? width,
    GifDither? dither,
    bool? loop,
  }) {
    return GifOptions(
      start: start ?? this.start,
      duration: duration != null ? duration() : this.duration,
      fps: fps ?? this.fps,
      width: width != null ? width() : this.width,
      dither: dither ?? this.dither,
      loop: loop ?? this.loop,
    );
  }
}

/// Single-command two-pass palette GIF (palettegen + paletteuse).
CommandPlan buildGif({
  required String input,
  required String output,
  required GifOptions options,
  MediaInfo? info,
}) {
  final o = options;
  if (info != null && !info.hasVideo) throw const PlanException('media.errors.no_video');
  final srcWidth = info?.video?.displayWidth ?? 0;
  final width = (o.width != null && (srcWidth == 0 || o.width! < srcWidth)) ? o.width : null;
  final filter = [
    'fps=${o.fps}',
    if (width != null) 'scale=$width:-1:flags=lanczos',
    'split[s0][s1]',
  ].join(',');
  final graph =
      '$filter;[s0]palettegen=stats_mode=diff[p];'
      '[s1][p]paletteuse=dither=${o.dither.value}:diff_mode=rectangle';

  final total = info?.duration;
  final expected = o.duration ?? (total != null && total > o.start ? total - o.start : null);

  return CommandPlan.single(
    [
      if (o.start > Duration.zero) ...['-ss', Fmt.seconds(o.start)],
      if (o.duration != null) ...['-t', Fmt.seconds(o.duration!)],
      '-i',
      input,
      '-filter_complex',
      graph,
      '-loop',
      o.loop ? '0' : '-1',
      '-n',
      output,
    ],
    output: output,
    expectedDuration: expected,
  );
}
