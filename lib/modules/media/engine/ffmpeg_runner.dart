import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'progress.dart';

class FfmpegExit {
  const FfmpegExit({
    required this.exitCode,
    required this.cancelled,
    required this.tail,
  });

  final int exitCode;
  final bool cancelled;

  /// Last stderr lines — the error explanation on failure.
  final List<String> tail;

  bool get ok => exitCode == 0 && !cancelled;

  /// Most useful error line: last line mentioning an error, else last line.
  String get errorSummary {
    final pattern = RegExp(r'error|invalid|no such|not |unable|failed|cannot|unknown', caseSensitive: false);
    for (final line in tail.reversed) {
      if (pattern.hasMatch(line)) return line;
    }
    return tail.isEmpty ? 'ffmpeg exited with code $exitCode' : tail.last;
  }
}

/// Runs ffmpeg as a child process (argv array — no shell), streaming
/// structured progress from `-progress pipe:1` and log lines from stderr.
abstract final class FfmpegRunner {
  static const progressArgs = ['-hide_banner', '-nostdin', '-progress', 'pipe:1', '-nostats'];

  static Future<FfmpegExit> run({
    required String ffmpeg,
    required List<String> args,
    void Function(FfmpegProgress progress)? onProgress,
    void Function(String line)? onLog,
    Future<void>? cancelSignal,
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      ffmpeg,
      [...progressArgs, ...args],
      workingDirectory: workingDirectory,
    );

    var cancelled = false;
    var exited = false;
    Timer? killTimer;
    if (cancelSignal != null) {
      unawaited(
        cancelSignal.then((_) {
          if (exited) return;
          cancelled = true;
          process.kill(ProcessSignal.sigterm);
          // Escalate if ffmpeg doesn't stop on its own.
          killTimer = Timer(const Duration(seconds: 3), () => process.kill(ProcessSignal.sigkill));
        }),
      );
    }

    final tail = <String>[];
    final parser = FfmpegProgressParser();
    const decoder = Utf8Decoder(allowMalformed: true);

    final stdoutDone = process.stdout.transform(decoder).transform(const LineSplitter()).forEach((line) {
      final p = parser.add(line);
      if (p != null) onProgress?.call(p);
    });
    final stderrDone = process.stderr
        .transform(decoder)
        // ffmpeg separates some messages with \r.
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isEmpty) return;
          tail.add(line);
          if (tail.length > 30) tail.removeAt(0);
          onLog?.call(line);
        });

    final code = await process.exitCode;
    exited = true;
    await Future.wait([stdoutDone, stderrDone]);
    killTimer?.cancel();
    return FfmpegExit(exitCode: code, cancelled: cancelled, tail: tail);
  }
}
