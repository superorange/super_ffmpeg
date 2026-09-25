import 'dart:convert';

import 'package:flutter/foundation.dart';

enum StreamKind { video, audio, subtitle, data, attachment, unknown }

@immutable
class MediaStream {
  const MediaStream({
    required this.index,
    required this.kind,
    this.codec = '',
    this.codecLong = '',
    this.profile,
    this.width = 0,
    this.height = 0,
    this.pixelFormat,
    this.frameRate,
    this.bitrate = 0,
    this.sampleRate = 0,
    this.channels = 0,
    this.channelLayout,
    this.language,
    this.title,
    this.rotation = 0,
    this.colorTransfer,
    this.bitDepth,
    this.isAttachedPicture = false,
    this.isDefault = false,
  });

  final int index;
  final StreamKind kind;
  final String codec;
  final String codecLong;
  final String? profile;
  final int width;
  final int height;
  final String? pixelFormat;
  final double? frameRate;
  final int bitrate;
  final int sampleRate;
  final int channels;
  final String? channelLayout;
  final String? language;
  final String? title;

  /// Display rotation in degrees (0/90/180/270), from the display matrix.
  final int rotation;
  final String? colorTransfer;
  final int? bitDepth;
  final bool isAttachedPicture;
  final bool isDefault;

  bool get isRotatedSideways => rotation == 90 || rotation == 270;
  int get displayWidth => isRotatedSideways ? height : width;
  int get displayHeight => isRotatedSideways ? width : height;

  /// PQ (HDR10) or HLG transfer.
  bool get isHdr => colorTransfer == 'smpte2084' || colorTransfer == 'arib-std-b67';

  factory MediaStream.fromJson(Map<String, dynamic> j) {
    final tags = (j['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
    final disposition = (j['disposition'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sideData = (j['side_data_list'] as List?) ?? const [];
    num? rotation;
    for (final s in sideData.whereType<Map>()) {
      if (s['rotation'] is num) rotation = s['rotation'] as num;
    }
    rotation ??= _num(tags['rotate']);
    return MediaStream(
      index: _int(j['index']),
      kind: switch (j['codec_type']) {
        'video' => StreamKind.video,
        'audio' => StreamKind.audio,
        'subtitle' => StreamKind.subtitle,
        'data' => StreamKind.data,
        'attachment' => StreamKind.attachment,
        _ => StreamKind.unknown,
      },
      codec: (j['codec_name'] as String?) ?? '',
      codecLong: (j['codec_long_name'] as String?) ?? '',
      profile: j['profile'] as String?,
      width: _int(j['width']),
      height: _int(j['height']),
      pixelFormat: j['pix_fmt'] as String?,
      frameRate: parseRate(j['avg_frame_rate'] as String?) ?? parseRate(j['r_frame_rate'] as String?),
      bitrate: _int(j['bit_rate']),
      sampleRate: _int(j['sample_rate']),
      channels: _int(j['channels']),
      channelLayout: j['channel_layout'] as String?,
      language: tags['language'] as String?,
      title: tags['title'] as String?,
      rotation: rotation == null ? 0 : ((rotation.round() % 360) + 360) % 360,
      colorTransfer: j['color_transfer'] as String?,
      bitDepth: _intOrNull(j['bits_per_raw_sample']),
      isAttachedPicture: disposition['attached_pic'] == 1,
      isDefault: disposition['default'] == 1,
    );
  }

  /// `30000/1001` → 29.97. Returns null for `0/0` and junk.
  static double? parseRate(String? rate) {
    if (rate == null) return null;
    final parts = rate.split('/');
    final n = double.tryParse(parts[0]);
    final d = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
    if (n == null || d == null || d == 0 || n == 0) return null;
    return n / d;
  }
}

@immutable
class MediaInfo {
  const MediaInfo({
    required this.path,
    this.formatName = '',
    this.formatLongName = '',
    this.duration = Duration.zero,
    this.sizeBytes = 0,
    this.bitrate = 0,
    this.streams = const [],
    this.tags = const {},
    this.rawJson = '',
  });

  final String path;
  final String formatName;
  final String formatLongName;
  final Duration duration;
  final int sizeBytes;
  final int bitrate;
  final List<MediaStream> streams;
  final Map<String, String> tags;
  final String rawJson;

  /// Same file viewed as a clip of [length] — used to plan tools against a
  /// timeline selection (bitrate budgets, progress, frame intervals).
  MediaInfo clipped(Duration length) => MediaInfo(
    path: path,
    formatName: formatName,
    formatLongName: formatLongName,
    duration: length,
    sizeBytes: duration > Duration.zero
        ? (sizeBytes * length.inMilliseconds / duration.inMilliseconds).round()
        : sizeBytes,
    bitrate: bitrate,
    streams: streams,
    tags: tags,
    rawJson: rawJson,
  );

  /// First real video stream (cover art excluded).
  MediaStream? get video {
    for (final s in streams) {
      if (s.kind == StreamKind.video && !s.isAttachedPicture) return s;
    }
    return null;
  }

  MediaStream? get audio {
    for (final s in streams) {
      if (s.kind == StreamKind.audio) return s;
    }
    return null;
  }

  bool get hasVideo => video != null;

  /// HEIF/AVIF still made of a tile grid: each stream is one tile, so the
  /// in-process decoder would only see a fragment — use the CLI instead.
  bool get isTiledImage =>
      duration == Duration.zero &&
      streams.where((s) => s.kind == StreamKind.video).length > 1 &&
      RegExp(r'\.(heic|heif|avif|hif)$', caseSensitive: false).hasMatch(path);
  bool get hasAudio => audio != null;
  bool get hasCoverArt => streams.any((s) => s.isAttachedPicture);

  List<MediaStream> of(StreamKind kind) => [
    for (final s in streams)
      if (s.kind == kind) s,
  ];

  factory MediaInfo.fromProbeJson(String path, String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final format = (root['format'] as Map?)?.cast<String, dynamic>() ?? const {};
    final streams = [
      for (final s in (root['streams'] as List? ?? const []).whereType<Map>())
        MediaStream.fromJson(s.cast<String, dynamic>()),
    ];
    final seconds = double.tryParse('${format['duration']}') ?? 0;
    final tags = (format['tags'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const <String, String>{};
    return MediaInfo(
      path: path,
      formatName: (format['format_name'] as String?) ?? '',
      formatLongName: (format['format_long_name'] as String?) ?? '',
      duration: Duration(microseconds: (seconds * 1000000).round()),
      sizeBytes: _int(format['size']),
      bitrate: _int(format['bit_rate']),
      streams: streams,
      tags: tags,
      rawJson: const JsonEncoder.withIndent('  ').convert(root),
    );
  }
}

int _int(Object? v) => _intOrNull(v) ?? 0;

int? _intOrNull(Object? v) => switch (v) {
  int i => i,
  num n => n.round(),
  String s => int.tryParse(s) ?? double.tryParse(s)?.round(),
  _ => null,
};

num? _num(Object? v) => switch (v) {
  num n => n,
  String s => num.tryParse(s),
  _ => null,
};
