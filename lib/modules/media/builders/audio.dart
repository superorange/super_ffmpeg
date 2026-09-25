import '../engine/command_plan.dart';
import '../engine/media_info.dart';

enum AudioFormat {
  mp3('mp3', 'libmp3lame', lossy: true),
  aac('m4a', 'aac', lossy: true),
  opus('opus', 'libopus', lossy: true),
  flac('flac', 'flac', lossy: false),
  wav('wav', 'pcm_s16le', lossy: false),

  /// Stream copy — bit-exact extraction in the source codec.
  original('', 'copy', lossy: false);

  const AudioFormat(this.extension, this.encoder, {required this.lossy});
  final String extension;
  final String encoder;
  final bool lossy;
}

class AudioOptions {
  const AudioOptions({
    this.format = AudioFormat.mp3,
    this.bitrateKbps = 192,
    this.sampleRate,
    this.channels,
    this.normalize = false,
    this.gainDb = 0,
  });

  final AudioFormat format;
  final int bitrateKbps;

  /// null = keep source.
  final int? sampleRate;
  final int? channels;

  /// EBU R128 loudness normalization to -16 LUFS.
  final bool normalize;
  final double gainDb;

  bool get hasFilters => normalize || gainDb != 0;

  AudioOptions copyWith({
    AudioFormat? format,
    int? bitrateKbps,
    int? Function()? sampleRate,
    int? Function()? channels,
    bool? normalize,
    double? gainDb,
  }) {
    return AudioOptions(
      format: format ?? this.format,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRate: sampleRate != null ? sampleRate() : this.sampleRate,
      channels: channels != null ? channels() : this.channels,
      normalize: normalize ?? this.normalize,
      gainDb: gainDb ?? this.gainDb,
    );
  }
}

/// File extension for a stream-copied audio codec.
String extensionForAudioCodec(String codec) => switch (codec) {
  'aac' || 'alac' => 'm4a',
  'mp3' => 'mp3',
  'opus' => 'opus',
  'vorbis' => 'ogg',
  'flac' => 'flac',
  'ac3' => 'ac3',
  'eac3' => 'eac3',
  _ when codec.startsWith('pcm_') => 'wav',
  _ => 'mka',
};

String audioExtension(AudioOptions o, MediaInfo? info) =>
    o.format == AudioFormat.original ? extensionForAudioCodec(info?.audio?.codec ?? '') : o.format.extension;

CommandPlan buildAudio({
  required String input,
  required String output,
  required AudioOptions options,
  MediaInfo? info,
}) {
  final o = options;
  if (info != null && !info.hasAudio) throw const PlanException('media.errors.no_audio');
  final args = <String>['-i', input, '-vn', '-sn', '-dn'];

  if (o.format == AudioFormat.original) {
    args.addAll(['-map', '0:a:0', '-c:a', 'copy']);
  } else {
    args.addAll(['-map', '0:a:0', '-c:a', o.format.encoder]);
    if (o.format.lossy) args.addAll(['-b:a', '${o.bitrateKbps}k']);

    final filters = [
      if (o.gainDb != 0) 'volume=${o.gainDb.toStringAsFixed(1)}dB',
      if (o.normalize) 'loudnorm=I=-16:TP=-1.5:LRA=11',
    ];
    if (filters.isNotEmpty) args.addAll(['-af', filters.join(',')]);

    // loudnorm resamples to 192 kHz internally — always pin the output rate.
    final sourceRate = info?.audio?.sampleRate ?? 0;
    final rate =
        o.sampleRate ?? (o.normalize || o.format == AudioFormat.opus ? (sourceRate > 0 ? sourceRate : 48000) : null);
    if (rate != null) {
      args.addAll(['-ar', '${o.format == AudioFormat.opus ? 48000 : rate}']);
    }

    final sourceChannels = info?.audio?.channels ?? 2;
    final channels = o.channels ?? (o.format == AudioFormat.mp3 && sourceChannels > 2 ? 2 : null);
    if (channels != null) args.addAll(['-ac', '$channels']);
  }
  args.addAll(['-n', output]);
  return CommandPlan.single(args, output: output, expectedDuration: info?.duration);
}
