import '../../media/engine/command_plan.dart';
import '../../media/engine/media_info.dart';

enum PictureFormat {
  jpg('jpg', lossy: true),
  png('png'),
  avif('avif', lossy: true),
  tiff('tiff'),
  bmp('bmp'),

  /// Same as the source when it's writable, else JPEG.
  original('');

  const PictureFormat(this.extension, {this.lossy = false});
  final String extension;
  final bool lossy;
}

class ImageOptions {
  const ImageOptions({this.format = PictureFormat.jpg, this.quality = 82, this.maxSide});

  final PictureFormat format;

  /// 1–100, lossy formats only.
  final int quality;

  /// Longest side in pixels; null keeps the size (never upscales).
  final int? maxSide;

  ImageOptions copyWith({PictureFormat? format, int? quality, int? Function()? maxSide}) => ImageOptions(
    format: format ?? this.format,
    quality: quality ?? this.quality,
    maxSide: maxSide != null ? maxSide() : this.maxSide,
  );
}

/// Extensions the bundled FFmpeg reads as still images (HEIC via the HEIF
/// demuxer, WebP via webp_pipe).
const imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'avif',
  'bmp',
  'tif',
  'tiff',
  'gif',
  'tga',
  'jp2',
  'jxl',
  'ico',
};

/// Resolves [PictureFormat.original] against the input extension.
PictureFormat effectiveFormat(PictureFormat f, String inputExt) {
  if (f != PictureFormat.original) return f;
  return switch (inputExt.toLowerCase()) {
    'jpg' || 'jpeg' => PictureFormat.jpg,
    'png' => PictureFormat.png,
    'avif' => PictureFormat.avif,
    'tif' || 'tiff' => PictureFormat.tiff,
    'bmp' => PictureFormat.bmp,
    _ => PictureFormat.jpg,
  };
}

/// One still image → one output. Metadata (EXIF, GPS) is always dropped;
/// orientation is baked into the pixels by FFmpeg's autorotation.
CommandPlan buildImageConvert({
  required String input,
  required String output,
  required PictureFormat format,
  required ImageOptions options,
  MediaInfo? info,
}) {
  final q = options.quality.clamp(1, 100);
  final side = options.maxSide;
  // Always emit the (no-op when already small) scale: probed sizes can be
  // wrong for tiled HEIC, where the first stream is a single 512px tile.
  final filters = [
    if (side != null) "scale='min($side,iw)':'min($side,ih)':force_original_aspect_ratio=decrease:flags=lanczos",
    // AV1 still images need even dimensions in 4:2:0.
    if (format == PictureFormat.avif) 'scale=trunc(iw/2)*2:trunc(ih/2)*2',
  ];
  final codec = switch (format) {
    // mjpeg qscale: 2 (best) … 31 (worst).
    PictureFormat.jpg => [
      '-c:v',
      'mjpeg',
      '-q:v',
      '${(31 - q * 29 / 100).round().clamp(2, 31)}',
      '-pix_fmt',
      'yuvj420p',
    ],
    PictureFormat.png => ['-c:v', 'png', '-compression_level', '9'],
    // svt-av1 CRF 63 (worst) … ~10 (near lossless), still-image tuning.
    PictureFormat.avif => [
      '-c:v',
      'libsvtav1',
      '-crf',
      '${(63 - q * 0.53).round().clamp(4, 63)}',
      '-svtav1-params',
      'avif=1',
      '-pix_fmt',
      'yuv420p',
      '-f',
      'avif',
    ],
    PictureFormat.tiff => ['-c:v', 'tiff', '-compression_algo', 'deflate'],
    PictureFormat.bmp => ['-c:v', 'bmp'],
    PictureFormat.original => throw ArgumentError('resolve with effectiveFormat first'),
  };
  return CommandPlan.single(
    [
      '-i',
      input,
      '-frames:v',
      '1',
      '-map_metadata',
      '-1',
      if (filters.isNotEmpty)
        // Tile grids are composed by an implicit complex graph, so filters
        // must hang off the stream group rather than use -vf.
        ...(info?.isTiledImage ?? false)
            ? ['-filter_complex', '[0:g:0]${filters.join(',')}[img]', '-map', '[img]']
            : ['-vf', filters.join(',')],
      ...codec,
      '-n',
      output,
    ],
    output: output,
  );
}
