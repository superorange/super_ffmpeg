import 'package:path/path.dart' as p;

import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import 'codecs.dart';

enum ConcatMode {
  /// Concat demuxer + stream copy. Requires identical codec parameters.
  fast,

  /// Normalize every clip (size, fps, audio layout) and re-encode.
  compatible,
}

class ConcatOptions {
  const ConcatOptions({this.mode = ConcatMode.compatible, this.preferGpu = true});
  final ConcatMode mode;
  final bool preferGpu;
}

/// Escapes a path for an ffconcat `file '…'` directive.
String ffconcatQuote(String path) => "'${path.replaceAll("'", r"'\''")}'";

String ffconcatList(List<String> inputs) =>
    ['ffconcat version 1.0', for (final i in inputs) 'file ${ffconcatQuote(i)}'].join('\n');

String concatExtension(List<String> inputs, ConcatMode mode) {
  if (mode == ConcatMode.compatible) return 'mp4';
  final ext = p.extension(inputs.first).replaceFirst('.', '').toLowerCase();
  return ext.isEmpty ? 'mp4' : ext;
}

CommandPlan buildConcat({
  required List<String> inputs,
  required String output,
  required ConcatOptions options,
  required Set<String> encoders,
  required String listPath,
  List<MediaInfo?> infos = const [],
}) {
  if (inputs.length < 2) throw const PlanException('media.errors.need_two_files');
  Duration? total;
  if (infos.length == inputs.length && infos.every((i) => i != null)) {
    total = infos.fold<Duration>(Duration.zero, (sum, i) => sum + i!.duration);
  }

  if (options.mode == ConcatMode.fast) {
    return CommandPlan(
      steps: [
        FfmpegStep(['-f', 'concat', '-safe', '0', '-i', listPath, '-c', 'copy', '-n', output]),
      ],
      outputs: [output],
      auxFiles: {listPath: ffconcatList(inputs)},
      expectedDuration: total,
    );
  }

  if (infos.length != inputs.length || infos.any((i) => i == null)) {
    throw const PlanException('media.errors.probe_pending');
  }
  final media = infos.cast<MediaInfo>();
  if (media.any((m) => !m.hasVideo)) throw const PlanException('media.errors.no_video');

  // Canvas follows the first clip; fps follows the first clip (capped at 60).
  final first = media.first.video!;
  final w = first.displayWidth.isEven ? first.displayWidth : first.displayWidth - 1;
  final h = first.displayHeight.isEven ? first.displayHeight : first.displayHeight - 1;
  final fps = ((first.frameRate ?? 30).clamp(1, 60) * 1000).round() / 1000;
  final withAudio = media.any((m) => m.hasAudio);

  final graph = StringBuffer();
  final pads = StringBuffer();
  for (var i = 0; i < media.length; i++) {
    graph.write(
      '[$i:v:0]scale=$w:$h:force_original_aspect_ratio=decrease,'
      'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=${fmtNum(fps)},format=yuv420p[v$i];',
    );
    pads.write('[v$i]');
    if (withAudio) {
      if (media[i].hasAudio) {
        graph.write(
          '[$i:a:0]aresample=48000,'
          'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[a$i];',
        );
      } else {
        // Silent filler so clips without audio don't break concat.
        final secs = media[i].duration.inMilliseconds / 1000;
        graph.write(
          'anullsrc=r=48000:cl=stereo,atrim=duration=${fmtNum(secs)},'
          'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo[a$i];',
        );
      }
      pads.write('[a$i]');
    }
  }
  graph.write('${pads}concat=n=${media.length}:v=1:a=${withAudio ? 1 : 0}[v]${withAudio ? '[a]' : ''}');

  final choice = Encoders.pick(VideoCodec.h264, encoders, preferGpu: options.preferGpu);
  if (choice == null) {
    throw const PlanException('media.errors.encoder_missing', {'codec': 'h264'});
  }

  return CommandPlan.single(
    [
      for (final i in inputs) ...['-i', i],
      '-filter_complex',
      graph.toString(),
      '-map',
      '[v]',
      if (withAudio) ...['-map', '[a]', '-c:a', 'aac', '-b:a', '192k'],
      '-c:v',
      choice.encoder,
      ...Encoders.quality(choice.encoder, QualityLevel.high),
      ...Encoders.extras(choice.encoder, MediaContainer.mp4),
      '-movflags',
      '+faststart',
      '-n',
      output,
    ],
    output: output,
    expectedDuration: total,
  );
}
