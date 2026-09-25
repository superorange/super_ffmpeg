import 'dart:io';

import 'package:path/path.dart' as p;

import 'native_media.dart' show devFfmpegRoot;

enum FfmpegSource {
  /// Shipped inside the app (scripts/build_ffmpeg.sh → embedded by Xcode).
  bundled,

  /// Folder chosen in Settings.
  custom,

  /// Found on the system (Homebrew, PATH…) — fallback only.
  system,
}

class FfmpegBinaries {
  const FfmpegBinaries({required this.ffmpeg, required this.ffprobe, this.source = FfmpegSource.system});
  final String ffmpeg;
  final String ffprobe;
  final FfmpegSource source;

  String get directory => p.dirname(ffmpeg);
}

/// Finds ffmpeg/ffprobe: a user-chosen folder wins, then the copy bundled in
/// the app, then the system (GUI apps on macOS don't inherit the shell PATH,
/// so package-manager locations are probed explicitly).
abstract final class FfmpegLocator {
  /// Where the bundled executables live: next to the app executable
  /// (Contents/MacOS) in a built app, `vendor/ffmpeg/<arch>/bin` in dev/tests.
  static List<String> bundledDirs() => [
    if (Platform.isMacOS) p.dirname(Platform.resolvedExecutable),
    p.join(devFfmpegRoot, 'bin'),
  ];

  static List<String> systemDirs({Map<String, String>? environment, String? operatingSystem}) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final env = environment ?? Platform.environment;
    final pathSep = os == 'windows' ? ';' : ':';
    return <String>{
      if (os == 'macos') ...['/opt/homebrew/bin', '/usr/local/bin', '/opt/local/bin'],
      if (os == 'linux') ...['/usr/bin', '/usr/local/bin', '/snap/bin'],
      if (os == 'windows') ...[
        r'C:\ffmpeg\bin',
        if (env['ProgramFiles'] != null) p.join(env['ProgramFiles']!, 'ffmpeg', 'bin'),
        if (env['USERPROFILE'] != null) p.join(env['USERPROFILE']!, 'scoop', 'shims'),
      ],
      ...?env['PATH']?.split(pathSep).where((d) => d.isNotEmpty),
    }.toList();
  }

  /// Ordered (dir, source) candidates.
  static List<(String, FfmpegSource)> candidates({
    String? customDir,
    List<String>? bundled,
    Map<String, String>? environment,
    String? operatingSystem,
    bool includeSystem = true,
  }) {
    final seen = <String>{};
    return [
      if (customDir != null && customDir.isNotEmpty) (customDir, FfmpegSource.custom),
      for (final d in bundled ?? bundledDirs()) (d, FfmpegSource.bundled),
      if (includeSystem)
        for (final d in systemDirs(environment: environment, operatingSystem: operatingSystem))
          (d, FfmpegSource.system),
    ].where((c) => seen.add(p.normalize(c.$1))).toList();
  }

  static FfmpegBinaries? locate({
    String? customDir,
    List<String>? bundled,
    bool includeSystem = true,
    Map<String, String>? environment,
    String? operatingSystem,
    bool Function(String path)? exists,
  }) {
    final check = exists ?? (String f) => File(f).existsSync();
    final exe = (operatingSystem ?? Platform.operatingSystem) == 'windows' ? '.exe' : '';
    for (final (dir, source) in candidates(
      customDir: customDir,
      bundled: bundled,
      includeSystem: includeSystem,
      environment: environment,
      operatingSystem: operatingSystem,
    )) {
      final ffmpeg = p.join(dir, 'ffmpeg$exe');
      final ffprobe = p.join(dir, 'ffprobe$exe');
      if (check(ffmpeg) && check(ffprobe)) {
        return FfmpegBinaries(ffmpeg: ffmpeg, ffprobe: ffprobe, source: source);
      }
    }
    return null;
  }
}
