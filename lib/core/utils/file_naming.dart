import 'dart:io';

import 'package:path/path.dart' as p;

/// Output path planning. Never overwrites an existing file.
abstract final class FileNaming {
  /// `/dir/clip.mov` + suffix `compressed` + ext `mp4` → `/outDir/clip_compressed.mp4`.
  static String derive({
    required String inputPath,
    required String extension,
    String suffix = '',
    String? outputDir,
  }) {
    final dir = outputDir ?? p.dirname(inputPath);
    final base = p.basenameWithoutExtension(inputPath);
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    final name = suffix.isEmpty ? base : '${base}_$suffix';
    return p.join(dir, '$name.$ext');
  }

  /// Returns [path] or `name (1).ext`, `name (2).ext`… — the first one for
  /// which [exists] is false. Paths in [reserved] are treated as taken, so a
  /// batch planned in one go never collides with itself.
  static String unique(
    String path, {
    Set<String> reserved = const {},
    bool Function(String path)? exists,
  }) {
    final taken = exists ?? (String x) => File(x).existsSync() || Directory(x).existsSync();
    bool isFree(String x) => !reserved.contains(x) && !taken(x);
    if (isFree(path)) return path;
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    for (var i = 1; i < 10000; i++) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (isFree(candidate)) return candidate;
    }
    throw StateError('Could not find a free file name for $path');
  }
}
