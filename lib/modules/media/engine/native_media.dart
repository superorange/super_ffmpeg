import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'media_info.dart';
import 'probe.dart' show ProbeException;

/// Architecture folder name used by scripts/build_ffmpeg.sh.
String get hostArchDir => Abi.current() == Abi.macosX64 ? 'darwin-x86_64' : 'darwin-arm64';

/// Root of the dev build of the bundled FFmpeg (`vendor/ffmpeg/darwin-*`),
/// honouring `SUPER_TOOLBOX_FFMPEG_DIR`.
String get devFfmpegRoot =>
    Platform.environment['SUPER_TOOLBOX_FFMPEG_DIR'] ?? p.join(Directory.current.path, 'vendor', 'ffmpeg', hostArchDir);

class DecodedFrame {
  const DecodedFrame(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  Future<ui.Image> toImage() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}

typedef _VersionC = Pointer<Utf8> Function();
typedef _ProbeC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _DecodeC = Pointer<Uint8> Function(
  Pointer<Utf8>,
  Int64,
  Int32,
  Int32,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Utf8>,
  Int32,
);
typedef _DecodeDart = Pointer<Uint8> Function(
  Pointer<Utf8>,
  int,
  int,
  int,
  Pointer<Int32>,
  Pointer<Int32>,
  Pointer<Utf8>,
  int,
);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

class _Bindings {
  _Bindings(DynamicLibrary lib)
    : version = lib.lookupFunction<_VersionC, _VersionC>('mb_version'),
      probe = lib.lookupFunction<_ProbeC, _ProbeC>('mb_probe'),
      decode = lib.lookupFunction<_DecodeC, _DecodeDart>('mb_decode_frame'),
      free = lib.lookupFunction<_FreeC, _FreeDart>('mb_free');

  final _VersionC version;
  final _ProbeC probe;
  final _DecodeDart decode;
  final _FreeDart free;

  static final _cache = <String, _Bindings>{};
  static _Bindings of(String path) => _cache.putIfAbsent(path, () => _Bindings(DynamicLibrary.open(path)));
}

/// In-process probing and frame decoding through the bundled libavformat /
/// libavcodec (native/src/media_bridge.c). Calls run on a background isolate.
abstract final class NativeMedia {
  static const libraryName = 'libmedia_bridge.dylib';

  static List<String> candidatePaths() => [
    if (Platform.isMacOS) p.join(p.dirname(Platform.resolvedExecutable), '..', 'Frameworks', libraryName),
    p.join(devFfmpegRoot, 'lib', libraryName),
  ];

  static String? _path;
  static bool _resolved = false;

  /// Path of a loadable bridge, or null when running without the bundle.
  static String? get libraryPath {
    if (_resolved) return _path;
    _resolved = true;
    for (final candidate in candidatePaths()) {
      if (!File(candidate).existsSync()) continue;
      try {
        _Bindings.of(candidate);
        return _path = p.normalize(candidate);
      } catch (_) {
        // Wrong arch or missing FFmpeg libs next to it — try the next one.
      }
    }
    return null;
  }

  static bool get isAvailable => libraryPath != null;

  static String? get version {
    final path = libraryPath;
    return path == null ? null : _Bindings.of(path).version().toDartString();
  }

  static Future<MediaInfo> probe(String file) {
    final lib = libraryPath ?? (throw StateError('media bridge unavailable'));
    return Isolate.run(() => probeSync(lib, file));
  }

  static MediaInfo probeSync(String lib, String file) {
    final b = _Bindings.of(lib);
    final cPath = file.toNativeUtf8();
    try {
      final json = b.probe(cPath);
      if (json == nullptr) throw const ProbeException('probe failed');
      final text = json.toDartString();
      b.free(json.cast());
      if (text.startsWith('{"error"')) {
        final msg = RegExp(r'"error":"((?:[^"\\]|\\.)*)"').firstMatch(text)?.group(1) ?? text;
        throw ProbeException(msg.replaceAll(r'\"', '"'));
      }
      return MediaInfo.fromProbeJson(file, text);
    } finally {
      malloc.free(cPath);
    }
  }

  /// Decodes the frame at [at] (or cover art) fitted into maxWidth×maxHeight.
  static Future<DecodedFrame> decodeFrame(
    String file, {
    Duration at = Duration.zero,
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    final lib = libraryPath ?? (throw StateError('media bridge unavailable'));
    final (w, h, data) = await Isolate.run(() {
      final f = decodeFrameSync(lib, file, at: at, maxWidth: maxWidth, maxHeight: maxHeight);
      return (f.width, f.height, TransferableTypedData.fromList([f.rgba]));
    });
    return DecodedFrame(w, h, data.materialize().asUint8List());
  }

  static DecodedFrame decodeFrameSync(
    String lib,
    String file, {
    Duration at = Duration.zero,
    int maxWidth = 0,
    int maxHeight = 0,
  }) {
    final b = _Bindings.of(lib);
    const errLen = 512;
    final cPath = file.toNativeUtf8();
    final w = malloc<Int32>();
    final h = malloc<Int32>();
    final err = malloc<Uint8>(errLen)..[0] = 0;
    try {
      final rgba = b.decode(cPath, at.inMicroseconds, maxWidth, maxHeight, w, h, err.cast(), errLen);
      if (rgba == nullptr) throw ProbeException(err.cast<Utf8>().toDartString());
      final bytes = Uint8List.fromList(rgba.asTypedList(w.value * h.value * 4));
      b.free(rgba.cast());
      return DecodedFrame(w.value, h.value, bytes);
    } finally {
      malloc
        ..free(cPath)
        ..free(w)
        ..free(h)
        ..free(err);
    }
  }
}
