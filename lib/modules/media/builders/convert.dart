import '../engine/command_plan.dart';
import '../engine/media_info.dart';
import 'codecs.dart';

enum AudioMode { auto, copy, remove }

enum FrameRateOption {
  original(null),
  fps60(60),
  fps30(30),
  fps24(24);

  const FrameRateOption(this.fps);
  final int? fps;
}

class ConvertOptions {
  const ConvertOptions({
    this.container = MediaContainer.mp4,
    this.codec = VideoCodec.h264,
    this.quality = QualityLevel.balanced,
    this.speed = EncodeSpeed.medium,
    this.resolution = Resolution.original,
    this.frameRate = FrameRateOption.original,
    this.audio = AudioMode.auto,
    this.preferGpu = true,
  });

  final MediaContainer container;
  final VideoCodec codec;
  final QualityLevel quality;
  final EncodeSpeed speed;
  final Resolution resolution;
  final FrameRateOption frameRate;
  final AudioMode audio;
  final bool preferGpu;

  ConvertOptions copyWith({
    MediaContainer? container,
    VideoCodec? codec,
    QualityLevel? quality,
    EncodeSpeed? speed,
    Resolution? resolution,
    FrameRateOption? frameRate,
    AudioMode? audio,
    bool? preferGpu,
  }) {
    return ConvertOptions(
      container: container ?? this.container,
      codec: codec ?? this.codec,
      quality: quality ?? this.quality,
      speed: speed ?? this.speed,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      audio: audio ?? this.audio,
      preferGpu: preferGpu ?? this.preferGpu,
    );
  }

  /// Selecting a codec the container can't hold switches the container.
  ConvertOptions withCodec(VideoCodec codec) => copyWith(
    codec: codec,
    container: container.supports(codec) ? container : MediaContainer.bestFor(codec),
  );

  /// Selecting a container that can't hold the codec switches the codec.
  ConvertOptions withContainer(MediaContainer c, Set<String> encoders) {
    if (c.supports(codec)) return copyWith(container: c);
    final fallback = c.codecs.firstWhere(
      (v) => v != VideoCodec.copy && v.isAvailable(encoders),
      orElse: () => VideoCodec.copy,
    );
    return copyWith(container: c, codec: fallback);
  }
}

CommandPlan buildConvert({
  required String input,
  required String output,
  required ConvertOptions options,
  required Set<String> encoders,
  MediaInfo? info,
}) {
  final o = options;
  final args = <String>['-i', input];

  if (o.codec == VideoCodec.copy) {
    args.addAll(['-c:v', 'copy']);
  } else {
    final choice = Encoders.pick(o.codec, encoders, preferGpu: o.preferGpu);
    if (choice == null) {
      throw PlanException('media.errors.encoder_missing', {'codec': o.codec.name});
    }
    final filters = [
      ?scaleFilter(o.resolution, info?.video),
      if (o.frameRate.fps case final fps?)
        if ((info?.video?.frameRate ?? double.infinity) > fps + 0.01) 'fps=$fps',
    ];
    args.addAll(['-c:v', choice.encoder]);
    args.addAll(Encoders.quality(choice.encoder, o.quality, speed: o.speed));
    args.addAll(Encoders.extras(choice.encoder, o.container));
    if (filters.isNotEmpty) args.addAll(['-vf', filters.join(',')]);
  }

  switch (o.audio) {
    case AudioMode.remove:
      args.add('-an');
    case AudioMode.copy:
      args.addAll(['-c:a', 'copy']);
    case AudioMode.auto:
      final enc = Encoders.audioEncoderFor(o.container, encoders);
      args.addAll(['-c:a', enc, '-b:a', enc == 'aac' ? '192k' : '160k']);
  }

  args.addAll(Encoders.containerFlags(o.container));
  args.addAll(['-n', output]);
  return CommandPlan.single(args, output: output, expectedDuration: info?.duration);
}
