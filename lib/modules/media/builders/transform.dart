import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import 'codecs.dart';

enum Rotation { none, cw90, ccw90, r180 }

/// Re-frame into a new aspect ratio over a blurred copy of the video.
enum Framing {
  original(null, null),
  vertical916(1080, 1920),
  square11(1080, 1080),
  landscape169(1920, 1080);

  const Framing(this.width, this.height);
  final int? width;
  final int? height;
}

class TransformOptions {
  const TransformOptions({
    this.speed = 1.0,
    this.rotation = Rotation.none,
    this.flipH = false,
    this.flipV = false,
    this.framing = Framing.original,
    this.mute = false,
    this.preferGpu = true,
  });

  final double speed;
  final Rotation rotation;
  final bool flipH;
  final bool flipV;
  final Framing framing;
  final bool mute;
  final bool preferGpu;

  bool get isIdentity =>
      speed == 1.0 && rotation == Rotation.none && !flipH && !flipV && framing == Framing.original && !mute;

  TransformOptions copyWith({
    double? speed,
    Rotation? rotation,
    bool? flipH,
    bool? flipV,
    Framing? framing,
    bool? mute,
    bool? preferGpu,
  }) {
    return TransformOptions(
      speed: speed ?? this.speed,
      rotation: rotation ?? this.rotation,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      framing: framing ?? this.framing,
      mute: mute ?? this.mute,
      preferGpu: preferGpu ?? this.preferGpu,
    );
  }
}

CommandPlan buildTransform({
  required String input,
  required String output,
  required TransformOptions options,
  required Set<String> encoders,
  MediaInfo? info,
}) {
  final o = options;
  if (o.isIdentity) throw const PlanException('media.errors.nothing_to_do');
  if (info != null && !info.hasVideo) throw const PlanException('media.errors.no_video');
  if (o.speed < 0.25 || o.speed > 4) throw const PlanException('media.errors.invalid_speed');

  final pre = [
    ...switch (o.rotation) {
      Rotation.none => const <String>[],
      Rotation.cw90 => ['transpose=clock'],
      Rotation.ccw90 => ['transpose=cclock'],
      Rotation.r180 => ['hflip', 'vflip'],
    },
    if (o.flipH) 'hflip',
    if (o.flipV) 'vflip',
    if (o.speed != 1.0) 'setpts=PTS/${fmtNum(o.speed)}',
  ];

  final choice = Encoders.pick(VideoCodec.h264, encoders, preferGpu: o.preferGpu);
  if (choice == null) {
    throw const PlanException('media.errors.encoder_missing', {'codec': 'h264'});
  }

  final args = <String>['-i', input];
  if (o.framing == Framing.original) {
    if (pre.isNotEmpty) args.addAll(['-vf', pre.join(',')]);
  } else {
    final w = o.framing.width!;
    final h = o.framing.height!;
    final head = pre.isEmpty ? '[0:v]' : '[0:v]${pre.join(',')},';
    args.addAll([
      '-filter_complex',
      '${head}split=2[bgsrc][fgsrc];'
          '[bgsrc]scale=$w:$h:force_original_aspect_ratio=increase,crop=$w:$h,gblur=sigma=40[bg];'
          '[fgsrc]scale=$w:$h:force_original_aspect_ratio=decrease[fg];'
          '[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1[vout]',
      '-map',
      '[vout]',
      if (!o.mute) ...['-map', '0:a?'],
    ]);
  }

  args.addAll(['-c:v', choice.encoder]);
  args.addAll(Encoders.quality(choice.encoder, QualityLevel.high));
  args.addAll(Encoders.extras(choice.encoder, MediaContainer.mp4));

  if (o.mute) {
    args.add('-an');
  } else {
    if (o.speed != 1.0) args.addAll(['-af', atempoChain(o.speed)]);
    args.addAll(['-c:a', 'aac', '-b:a', '192k']);
  }
  args.addAll(['-movflags', '+faststart', '-n', output]);

  final duration = info?.duration;
  return CommandPlan.single(
    args,
    output: output,
    expectedDuration: duration == null ? null : Duration(microseconds: (duration.inMicroseconds / o.speed).round()),
  );
}
